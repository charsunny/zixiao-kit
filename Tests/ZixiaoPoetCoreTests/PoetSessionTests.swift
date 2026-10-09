import Foundation
import XCTest
import ZixiaoCore
import ZixiaoPoetCore

@MainActor
final class PoetSessionTests: XCTestCase {
    func testOneSessionSharesAnEditionButKeepsEditionDataSeparate() async throws {
        let suite = "PoetSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let remote = RecordingRemote()
        let queue = ZXOutbox(fileURL: root.appendingPathComponent("outbox.json"),
                             transport: NoUpload(), policy: .init(autoDrain: false))
        let auth = ZXAuth(outbox: queue)
        let session = PoetSession(auth: auth, remote: remote, cache: .init(defaults: defaults))
        let first = session.userData(for: "edition-a")
        let second = session.userData(for: "edition-b")
        XCTAssertTrue(session.outbox === queue)
        XCTAssertTrue(session.auth === auth)
        XCTAssertTrue(first === session.userData(for: "edition-a"))
        XCTAssertFalse(first === second)

        try await first.saveNote(targetType: "poem", targetId: UUID(), body: "第一册的批注")
        XCTAssertEqual(first.notes.count, 1)
        XCTAssertTrue(second.notes.isEmpty)
        try await second.saveNote(targetType: "poem", targetId: UUID(), body: "第二册的批注")
        await session.start(localOnly: true)
        XCTAssertFalse(auth.isBootstrapped)
        let fetchCount = await remote.fetchCount
        let pendingCount = await queue.pendingCount
        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(pendingCount, 0)

        session.clearLocal(for: nil)
        XCTAssertTrue(first.notes.isEmpty)
        XCTAssertTrue(second.notes.isEmpty)
        XCTAssertTrue(PoetUserDataCache(defaults: defaults).load(app: "edition-a", owner: nil).isEmpty)
        XCTAssertTrue(PoetUserDataCache(defaults: defaults).load(app: "edition-b", owner: nil).isEmpty)
    }

    func testSameResourceNamesStayBoundToTheirOwnDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try resources(at: root.appendingPathComponent("a"), title: "第一册")
        let second = try resources(at: root.appendingPathComponent("b"), title: "第二册")
        XCTAssertNotEqual(first.url(forAsset: "cover.jpg"), second.url(forAsset: "cover.jpg"))
        XCTAssertEqual(try first.collections()?.collections.first?.title, "第一册")
        XCTAssertEqual(try second.collections()?.collections.first?.title, "第二册")
        XCTAssertEqual(try first.collections()?.collections.first?.title, "第一册")
    }

    private func resources(at directory: URL, title: String) throws -> PoetResources {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let collections = PoetCollections(poet: "test", collections: [
            .init(id: "selection", title: title, thesis: "", intro: "", placeSeed: "test", workIds: []),
        ])
        try JSONEncoder().encode(collections).write(to: directory.appendingPathComponent("collections-test.json"))
        try Data(title.utf8).write(to: directory.appendingPathComponent("cover.jpg"))
        return PoetResources(bundleURL: directory, slug: "test", productName: title)
    }
}

private actor RecordingRemote: PoetUserDataRemote {
    private(set) var fetchCount = 0
    func fetch(ownerKey: String, app: String) async throws -> PoetRemoteRows {
        fetchCount += 1
        return PoetRemoteRows()
    }
    func deleteBookmark(ownerKey: String, app: String, targetType: String, targetId: UUID) async throws {}
}

private struct NoUpload: ZXOutboxTransport {
    func deliver(_ entry: ZXOutboxEntry) async -> ZXOutboxDelivery { .rejected("Unexpected upload in local test") }
}
