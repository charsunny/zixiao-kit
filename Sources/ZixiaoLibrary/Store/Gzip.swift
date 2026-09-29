import Compression
import Foundation

/// gzip (RFC 1952) 解压。
///
/// 为什么自己拆 gzip 头: libcompression 的 `COMPRESSION_ZLIB` 只认**裸 deflate** (RFC 1951),
/// 既不认 zlib 头也不认 gzip 头; Foundation 的 `NSData.decompressed(using: .zlib)` 同样是裸 deflate。
/// 云端 `book.json.gz` 是 `gzip -9` 产物, 前面有 10+ 字节头、后面有 8 字节尾, 所以要自己剥掉,
/// 再用尾部的 CRC32 与长度核一遍。这样不引入任何第三方依赖 (README 的规则)。
public enum Gzip {
    public enum Failure: Error, Sendable, Equatable {
        case notGzip
        case unsupportedMethod(UInt8)
        case truncated
        case corrupt
        case checksumMismatch
        case lengthMismatch
        case tooLarge
    }

    /// 前两个字节是 1f 8b。用来区分「服务器按 Content-Encoding 已经替我们解过」与「拿到的是 .gz 原始字节」。
    public static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// - Parameter limit: 解压后上限 (字节)。防压缩炸弹; 一本书的 JSON 远小于默认 64 MB。
    public static func decompress(_ data: Data, limit: Int = 64 << 20) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { throw isGzip(data) ? Failure.truncated : Failure.notGzip }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b else { throw Failure.notGzip }
        guard bytes[2] == 8 else { throw Failure.unsupportedMethod(bytes[2]) }
        let flags = bytes[3]
        var offset = 10
        // FEXTRA: 两字节小端长度 + 数据。
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw Failure.truncated }
            offset += 2 + (Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8))
        }
        // FNAME / FCOMMENT: 以 0 结尾的 Latin-1 串。
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC: 头部 CRC16, 不校 (尾部 CRC32 已覆盖正文)。
        if flags & 0x02 != 0 { offset += 2 }
        guard offset <= bytes.count - 8 else { throw Failure.truncated }

        let trailer = bytes.count - 8
        let expectedCRC = littleEndian32(bytes, at: trailer)
        let expectedSize = littleEndian32(bytes, at: trailer + 4)

        let output = try inflate(bytes[offset..<trailer], limit: limit)
        // ISIZE 是原长模 2^32。
        guard UInt32(truncatingIfNeeded: output.count) == expectedSize else { throw Failure.lengthMismatch }
        guard CRC32.checksum(output) == expectedCRC else { throw Failure.checksumMismatch }
        return output
    }

    /// 裸 deflate 流式解压。用 stream API 而不是 `compression_decode_buffer`,
    /// 因为后者要预先给足输出缓冲, 而 ISIZE 只是模 2^32 的提示, 不可全信。
    static func inflate(_ input: ArraySlice<UInt8>, limit: Int) throws -> Data {
        guard !input.isEmpty else { throw Failure.truncated }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.corrupt
        }
        defer { compression_stream_destroy(stream) }

        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var output = Data()

        try input.withUnsafeBufferPointer { source in
            stream.pointee.src_ptr = source.baseAddress!
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.pointee.dst_size
                output.append(buffer, count: produced)
                if output.count > limit { throw Failure.tooLarge }
                switch status {
                case COMPRESSION_STATUS_END:
                    return
                case COMPRESSION_STATUS_OK:
                    // 输入耗尽却没有新输出也没到 END: 流被截断, 继续循环只会空转。
                    if produced == 0 && stream.pointee.src_size == 0 { throw Failure.truncated }
                default:
                    throw Failure.corrupt
                }
            }
        }
        return output
    }

    private static func littleEndian32(_ bytes: [UInt8], at i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
    }
}

/// IEEE 802.3 CRC32 (gzip 用的那个)。系统 zlib 没有 Swift 模块可直接 import, 自己算一张表更省事。
enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
