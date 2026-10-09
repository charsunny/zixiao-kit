import Foundation
import ZixiaoCore

/// An application owns one session and queue, while each content edition keeps its existing
/// user-data namespace. Sharing this container also keeps multiple windows on the same snapshot.
@MainActor
public final class PoetSession {
    public static let shared = PoetSession()

    public let auth: ZXAuth
    public let outbox: ZXOutbox
    private let remote: any PoetUserDataRemote
    private let cache: PoetUserDataCache
    private var editions: [String: PoetUserData] = [:]
    private var registered: [PoetUserData] = []
    private var hasStartedMonitoring = false

    public init(auth: ZXAuth? = nil, outbox: ZXOutbox? = nil,
                remote: any PoetUserDataRemote = PostgrestPoetUserDataRemote(),
                cache: PoetUserDataCache = PoetUserDataCache()) {
        let queue = outbox ?? auth?.syncOutbox ?? ZXOutbox(transport: ZXSupabaseOutboxTransport())
        self.outbox = queue
        self.auth = auth ?? ZXAuth(backend: ZXSupabaseAuthBackend(), outbox: queue)
        self.remote = remote
        self.cache = cache
    }

    /// `app` is the original edition's namespace, not the desktop application's bundle suffix.
    public func userData(for app: String) -> PoetUserData {
        if let existing = editions[app] { return existing }
        let data = PoetUserData(app: app, outbox: outbox, remote: remote, cache: cache)
        editions[app] = data
        register(data)
        return data
    }

    func register(_ data: PoetUserData) {
        guard !registered.contains(where: { $0 === data }) else { return }
        registered.append(data)
        if hasStartedMonitoring { data.attach(auth) }
    }

    /// Local-only validation leaves both the auth backend and upload transport untouched.
    public func start(localOnly: Bool = false) async {
        guard !localOnly else { return }
        for data in registered { data.attach(auth) }
        if !hasStartedMonitoring {
            hasStartedMonitoring = true
            await outbox.startMonitoring()
        }
        await auth.bootstrap()
    }

    /// The server's account deletion applies to every edition, so all registered caches must clear.
    public func clearLocal(for userID: String?) {
        for data in registered { data.clearLocal(for: userID) }
    }
}
