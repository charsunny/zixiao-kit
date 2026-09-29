import Foundation

/// 测试样书的位置: 从 testTarget 的资源 bundle (`Bundle.module`) 取。
///
/// 不再用 `#filePath` 读源码目录: Mac Catalyst 的测试进程受 TCC 限制, 读不了外接卷上的源码目录。
/// 两种资源声明都认: `.process("Resources")` 把文件拍平到 bundle 根; `.copy(...)` 保留子目录。
enum Fixtures {
    static let directory: URL = {
        let bundle = Bundle.module
        if let lunyu = bundle.url(forResource: "lunyu", withExtension: "json") {
            return lunyu.deletingLastPathComponent()
        }
        return bundle.resourceURL!.appendingPathComponent("Resources", isDirectory: true)
    }()

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    /// 心经 v1 在云端目录里的 hash (对解压后 book.json 字节)。
    static let xinjingHash = "sha256:4c189e35e6359c937c8dc2cdb33ba8b3884af78c6edc566d48da66eb687df71c"

    /// 每个用例一个临时目录, 用完即删。
    static func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZixiaoLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
