import Foundation
import XCTest
@testable import ZixiaoCore

/// Contract regressions: commit-before-reply, cross-account responses, tombstones and conflict resolution.
@MainActor final class CloudLibraryTests: XCTestCase {
    private func draft(_ title: String) -> ZXCloudLibraryDraft {
        .init(key: "favorite:poetryhub:poem:original", kind: "favorite",
              contentRef: .init(source: "poetryhub", kind: "poem", id: "original"),
              payload: ["title": .string(title)], updatedAt: "2026-10-01T00:00:00Z")
    }
    private func fixture() -> (CloudWireFixture, URL, URLSession) {
        let wire = CloudWireFixture()
        let base = URL(string: "https://\(UUID().uuidString.lowercased()).example.invalid")!
        CloudWireProtocol.register(host: base.host!, fixture: wire)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudWireProtocol.self]
        return (wire, base, URLSession(configuration: configuration))
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("cloud-library-test-" + UUID().uuidString) }
    private func client(_ wire: CloudWireFixture, _ base: URL, _ session: URLSession, _ directory: URL) -> ZXCloudLibraryClient {
        ZXCloudLibraryClient(baseURL: base, app: "test", directory: directory, urlSession: session,
                             sessionProvider: { wire.session() })
    }

    func testRetryAfterServerCommitReusesFrozenMutationAcrossRelaunch() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        let first = client(wire, base, session, directory)
        wire.failNextReply()
        try await first.enqueue(draft("原句"))
        do { try await first.synchronize(); XCTFail("Expected a lost acknowledgement") } catch { }
        let second = client(wire, base, session, directory)
        let rows = try await second.synchronize()
        XCTAssertEqual(rows.count, 1)
        let posts = wire.posts()
        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts[0], posts[1], "Retry must keep the original revision and clientMutationId")
        let pending = try await second.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testRevertWhileAttemptedWriteIsPendingIsNotLost() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        let client = client(wire, base, session, directory)
        try await client.enqueue(draft("甲")); try await client.synchronize()
        wire.failNextReply()
        try await client.enqueue(draft("乙"))
        do { try await client.synchronize(); XCTFail("Expected a lost acknowledgement") } catch { }
        try await client.enqueue(draft("甲"))
        let rows = try await client.synchronize()
        XCTAssertEqual(rows.first?.payload["title"], .string("甲"))
        XCTAssertEqual(rows.first?.revision, 3)
    }

    func testUnknownPayloadFieldsSurviveEditsAndDeletionKeepsATombstone() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        var original = draft("云端")
        original.payload["future"] = .object(["format": .int(2), "data": .array([.string("kept")])])
        wire.seed(original, revision: 1)
        let client = client(wire, base, session, directory)
        try await client.synchronize()
        try await client.applied(snapshot: [draft("云端")], scope: "favorites")
        try await client.reconcile(snapshot: [draft("本机改名")], scope: "favorites")
        var rows = try await client.synchronize()
        XCTAssertEqual(rows.first?.payload["future"], original.payload["future"])
        try await client.reconcile(snapshot: [], scope: "favorites")
        rows = try await client.synchronize()
        XCTAssertNotNil(rows.first?.deletedAt)
        XCTAssertEqual(rows.first?.payload["future"], original.payload["future"])
    }

    func testReplyFromPreviousAccountIsNeverAppliedToNewOwner() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        let client = client(wire, base, session, directory)
        try await client.enqueue(draft("仅甲账号")); wire.switchAfterNextReply(to: "owner-b")
        do { try await client.synchronize(); XCTFail("Expected account boundary error") }
        catch let failure as ZXCloudLibraryError { guard case .accountChanged = failure else { return XCTFail("\(failure)") } }
        let newOwner = try await client.currentDrafts()
        XCTAssertTrue(newOwner.isEmpty)
        wire.setOwner("owner-a")
        let pending = try await client.pendingCount()
        XCTAssertEqual(pending, 1)
        let recovered = try await client.synchronize()
        XCTAssertEqual(recovered.first?.draft.title, "仅甲账号")
    }

    func testOlderReadingConflictAutomaticallyUsesNewerRemotePosition() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        var first = draft("初读"); first.kind = "reading"; first.key = "reading:poetryhub:poem:original"
        first.contentRef.anchor = .string("chapter:1")
        wire.seed(first, revision: 1)
        let client = client(wire, base, session, directory)
        try await client.synchronize()
        var remote = first; remote.updatedAt = "2026-10-01T00:02:00.500Z"; remote.contentRef.anchor = .string("chapter:9")
        wire.seed(remote, revision: 2)
        var old = first; old.updatedAt = "2026-10-01T00:01:00Z"; old.contentRef.anchor = .string("chapter:4")
        try await client.enqueue(old)
        let received = try await client.synchronize()
        let conflicts = try await client.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        XCTAssertEqual(received.first?.contentRef.anchor, .string("chapter:9"))
        XCTAssertEqual(wire.posts().count, 1)
    }

    func testReadingResolutionNeverConsumesDeletesIdentityChangesOrOtherKinds() {
        var draft = draft("读到这里"); draft.kind = "reading"
        let local = ZXCloudLibraryMutation(draft: draft, revision: 1)
        var remote = ZXCloudLibraryRecord(key: local.key, kind: local.kind, contentRef: local.contentRef,
            payload: local.payload, revision: 2, updatedAt: "2026-10-01T08:00:00.001+08:00", deletedAt: nil,
            serverCursor: "2", conflictOf: nil)
        XCTAssertTrue(ZXCloudLibraryReadingResolution.accepts(remote: remote, insteadOf: local))
        remote.deletedAt = "2026-10-01T00:01:00Z"
        XCTAssertFalse(ZXCloudLibraryReadingResolution.accepts(remote: remote, insteadOf: local))
        remote.deletedAt = nil; remote.contentRef.id = "another"
        XCTAssertFalse(ZXCloudLibraryReadingResolution.accepts(remote: remote, insteadOf: local))
        remote.contentRef.id = local.contentRef.id; remote.kind = "favorite"
        XCTAssertFalse(ZXCloudLibraryReadingResolution.accepts(remote: remote, insteadOf: local))
    }

    func testChoosingCloudConflictDoesNotRequeueStaleNativeSnapshot() async throws {
        let (wire, base, session) = fixture(); let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel() }
        wire.seed(draft("初版"), revision: 1)
        let client = client(wire, base, session, directory)
        try await client.synchronize()
        try await client.applied(snapshot: [draft("初版")], scope: "favorites")
        wire.seed(draft("云端新稿"), revision: 2)
        var local = [draft("本机改名")]
        let driver = ZXCloudLibraryDriver(client: client, scope: "favorites")
        driver.configure(owner: "owner-a", snapshot: { local }, apply: { local = $0 })
        await driver.synchronize()
        let conflict = try XCTUnwrap(driver.conflicts.first)
        await driver.resolve(conflict, keepLocal: false)
        XCTAssertEqual(local.first?.title, "云端新稿")
        XCTAssertTrue(driver.conflicts.isEmpty)
        XCTAssertEqual(wire.posts().count, 1, "Choosing cloud must not submit the stale local value again")
    }
}

private final class CloudWireFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var owner = "owner-a"
    private var switchOwner: String?
    private var failReply = false
    private var rows: [String: [String: Any]] = [:]
    private var receipts: [String: [String: Any]] = [:]
    private var sent: [Data] = []
    private var cursor = 0
    func session() -> ZXCloudLibrarySession { lock.withLock { .init(userID: owner, accessToken: "fixture-token") } }
    func setOwner(_ owner: String) { lock.withLock { self.owner = owner } }
    func switchAfterNextReply(to owner: String) { lock.withLock { switchOwner = owner } }
    func failNextReply() { lock.withLock { failReply = true } }
    func posts() -> [Data] { lock.withLock { sent } }
    func seed(_ draft: ZXCloudLibraryDraft, revision: Int) {
        lock.withLock {
            var row = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
            cursor += 1; row["revision"] = revision; row["serverCursor"] = String(cursor); rows[draft.key] = row
        }
    }
    func respond(_ request: URLRequest) throws -> (Data, Int) {
        try lock.withLock {
            defer { if let switchOwner { owner = switchOwner; self.switchOwner = nil } }
            if request.httpMethod == "POST" {
                let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let mutations = object["items"] as! [[String: Any]]
                sent.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                let result = mutations.map { mutation -> [String: Any] in
                    let id = mutation["clientMutationId"] as! String
                    if let receipt = receipts[id] { return receipt }
                    let key = mutation["key"] as! String; let previous = rows[key]
                    let revision = previous?["revision"] as? Int ?? 0
                    if revision != mutation["revision"] as! Int { return ["clientMutationId": id, "status": "conflict", "item": previous!] }
                    var row = mutation; cursor += 1; row["revision"] = revision + 1; row["serverCursor"] = String(cursor)
                    row.removeValue(forKey: "clientMutationId"); rows[key] = row
                    let receipt: [String: Any] = ["clientMutationId": id, "status": "applied", "item": row]
                    receipts[id] = receipt; return receipt
                }
                if failReply { failReply = false; return (Data("{}".utf8), 503) }
                return (try JSONSerialization.data(withJSONObject: ["results": result]), 200)
            }
            return (try JSONSerialization.data(withJSONObject: ["items": Array(rows.values), "nextCursor": String(cursor), "hasMore": false]), 200)
        }
    }
}

private final class CloudWireProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: CloudWireFixture] = [:]
    static func register(host: String, fixture: CloudWireFixture) { lock.withLock { fixtures[host] = fixture } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let fixture = Self.lock.withLock({ Self.fixtures[request.url!.host!] }) else { throw URLError(.badURL) }
            var copy = request
            if copy.httpBody == nil, let stream = copy.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
                copy.httpBody = data
            }
            let (data, status) = try fixture.respond(copy)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
