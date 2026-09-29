import Foundation
import Network

/// 网络可达性的来源。抽成 protocol 是为了测试里手动推「断 / 通」, 不依赖真实网络。
public protocol ZXConnectivity: Sendable {
    /// 每次网络状态变化产出一次, true = 可用。订阅开始时应先报一次当前状态。
    func updates() -> AsyncStream<Bool>
}

/// NWPathMonitor 的包装。每次 `updates()` 起一个新的 monitor, 流结束 (订阅方取消) 时停掉它。
///
/// 为什么每个订阅一个 monitor: NWPathMonitor 取消后不能重启, 共享一个就得自己管引用计数;
/// 订阅方只有离线队列一个, 这样最简单。
public struct ZXPathMonitor: ZXConnectivity {
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "ZixiaoCore.ZXPathMonitor", qos: .utility))
        }
    }
}
