import Foundation
import CryptoKit

/// Account-isolated, crash-safe sync. Tokens are supplied for each request and never stored here.
public actor ZXCloudLibraryClient {
    public typealias SessionProvider = @Sendable () async throws -> ZXCloudLibrarySession
    private struct Pending: Codable { var mutation: ZXCloudLibraryMutation; var attempted = false }
    private struct Document: Codable {
        var schema = 1
        var cursor = "0"
        var records: [String: ZXCloudLibraryRecord] = [:]
        var pending: [Pending] = []
        var conflicts: [ZXCloudLibraryConflict] = []
        var snapshots: [String: [String: ZXCloudLibraryDraft]] = [:]
        var assetIDs: [String: String] = [:]
    }
    private struct Page: Decodable { var items: [ZXCloudLibraryRecord]; var nextCursor: String; var hasMore: Bool }
    private struct Push: Encodable { let items: [ZXCloudLibraryMutation] }
    private struct Result: Decodable { let clientMutationId: String; let status: String; let item: ZXCloudLibraryRecord }
    private struct Results: Decodable { let results: [Result] }
    private let directory: URL
    private let baseURL: URL
    private let app: String
    private let sessionProvider: SessionProvider
    private let urlSession: URLSession
    private var documents: [String: Document] = [:]
    private var busyOwners = Set<String>()

    public init(baseURL: URL, app: String, directory: URL? = nil, urlSession: URLSession = .shared,
                sessionProvider: @escaping SessionProvider) {
        self.baseURL = baseURL; self.app = app; self.urlSession = urlSession; self.sessionProvider = sessionProvider
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZixiaoCloudLibrary", isDirectory: true)
    }

    public func currentOwner() async throws -> String { try await sessionProvider().userID }
    public func records() async throws -> [ZXCloudLibraryRecord] { Array(try load(try await currentOwner()).records.values) }
    public func conflicts() async throws -> [ZXCloudLibraryConflict] { try load(try await currentOwner()).conflicts }
    /// Current local view includes offline edits and unresolved conflicts, so applying a pull never discards them.
    public func currentDrafts(expectedOwner: String? = nil) async throws -> [ZXCloudLibraryDraft] {
        let document = try load(try await scopedOwner(expectedOwner))
        var result = document.records.mapValues(\.draft)
        for conflict in document.conflicts { result[conflict.local.key] = conflict.local.draft }
        for pending in document.pending { result[pending.mutation.key] = pending.mutation.draft }
        return result.values.sorted { $0.key < $1.key }
    }
    public func pendingCount() async throws -> Int { try load(try await currentOwner()).pending.count }

    public func enqueue(_ draft: ZXCloudLibraryDraft) async throws {
        let owner = try await currentOwner()
        var document = try load(owner)
        append(draft, to: &document)
        try save(document, owner: owner)
    }

    /// Snapshot input must already belong to this account. Legacy data is passed only after an explicit preview confirmation.
    public func reconcile(snapshot: [ZXCloudLibraryDraft], scope: String, expectedOwner: String? = nil) async throws {
        let owner = try await scopedOwner(expectedOwner)
        var document = try load(owner)
        let current = Dictionary(snapshot.map { ($0.key, $0) }, uniquingKeysWith: { _, newer in newer })
        let previous = document.snapshots[scope] ?? [:]
        for (key, value) in current where previous[key] != value { append(value, to: &document) }
        for (key, old) in previous where current[key] == nil {
            var tombstone = old
            tombstone.deletedAt = ZXCloudLibraryJSON.timestamp(); tombstone.updatedAt = tombstone.deletedAt!
            append(tombstone, to: &document)
        }
        document.snapshots[scope] = current
        try save(document, owner: owner)
    }

    /// Mark the exact successfully-applied view of local stores; remote changes must not echo as new writes.
    public func applied(snapshot: [ZXCloudLibraryDraft], scope: String, expectedOwner: String? = nil) async throws {
        let owner = try await scopedOwner(expectedOwner)
        var document = try load(owner)
        document.snapshots[scope] = Dictionary(snapshot.map { ($0.key, $0) }, uniquingKeysWith: { _, newer in newer })
        try save(document, owner: owner)
    }

    public func resolveConflict(id: String, keepLocal: Bool, expectedOwner: String? = nil) async throws {
        let owner = try await scopedOwner(expectedOwner)
        var document = try load(owner)
        guard let conflict = document.conflicts.first(where: { $0.id == id }) else { return }
        let chosenLocal = document.pending.last(where: { $0.mutation.key == conflict.local.key })?.mutation.draft ?? conflict.local.draft
        document.conflicts.removeAll { $0.id == id }
        document.pending.removeAll { $0.mutation.key == conflict.local.key }
        if keepLocal { append(chosenLocal, to: &document) }
        try save(document, owner: owner)
    }

    @discardableResult public func synchronize(expectedOwner: String? = nil) async throws -> [ZXCloudLibraryRecord] {
        let owner = try await scopedOwner(expectedOwner)
        guard busyOwners.insert(owner).inserted else { throw ZXCloudLibraryError.busy }
        defer { busyOwners.remove(owner) }
        while true {
            var document = try load(owner)
            var keys = Set(document.conflicts.map { $0.local.key })
            var batch: [ZXCloudLibraryMutation] = []
            for index in document.pending.indices where batch.count < 50 {
                let key = document.pending[index].mutation.key
                guard keys.insert(key).inserted else { continue }
                if !document.pending[index].attempted {
                    document.pending[index].mutation.revision = document.records[key]?.revision ?? 0
                    document.pending[index].attempted = true
                }
                let candidate = batch + [document.pending[index].mutation]
                let encodedSize = try JSONEncoder().encode(Push(items: candidate)).count
                if !batch.isEmpty && encodedSize > 900_000 { break }
                batch = candidate
            }
            guard !batch.isEmpty else { break }
            try save(document, owner: owner) // Freeze UUID, payload and revision before the first network attempt.
            let data = try await request(path: "api/v1/library/sync", method: "POST", body: JSONEncoder().encode(Push(items: batch)), owner: owner)
            let response = try JSONDecoder().decode(Results.self, from: data)
            guard Set(response.results.map(\.clientMutationId)) == Set(batch.map(\.clientMutationId)),
                  response.results.allSatisfy({ ["applied", "conflict", "forked"].contains($0.status) }) else { throw ZXCloudLibraryError.invalidResponse }
            document = try load(owner) // An edit may have been queued while the HTTP request was in flight.
            for result in response.results {
                if result.status == "conflict", let local = document.pending.first(where: { $0.mutation.id == result.clientMutationId })?.mutation {
                    if !ZXCloudLibraryReadingResolution.accepts(remote: result.item, insteadOf: local) {
                        document.conflicts.append(.init(local: local, remote: result.item))
                    }
                }
                if result.item.revision >= (document.records[result.item.key]?.revision ?? 0) { document.records[result.item.key] = result.item }
                document.pending.removeAll { $0.mutation.id == result.clientMutationId }
            }
            try save(document, owner: owner)
        }
        while true {
            let cursor = try load(owner).cursor
            let data = try await request(path: "api/v1/library/sync?cursor=\(cursor)&limit=100", owner: owner)
            let page = try JSONDecoder().decode(Page.self, from: data)
            guard let next = UInt64(page.nextCursor), let old = UInt64(cursor), next >= old,
                  !page.hasMore || next > old else { throw ZXCloudLibraryError.invalidResponse }
            var document = try load(owner)
            for item in page.items {
                if item.revision >= (document.records[item.key]?.revision ?? 0) { document.records[item.key] = item }
            }
            document.cursor = page.nextCursor
            try save(document, owner: owner) // Data and cursor share one atomic file replacement.
            if !page.hasMore { return Array(document.records.values) }
        }
    }

    /// Photo data goes to a private, owner-scoped object; the JSON payload contains only its asset ID.
    public func uploadPhoto(_ data: Data, contentType: String = "image/jpeg", expectedOwner: String? = nil) async throws -> String {
        let owner = try await scopedOwner(expectedOwner)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let id = try load(owner).assetIDs[hash] { return id }
        struct Reservation: Decodable { let assetId: String; let uploadUrl: URL }
        let body = try JSONSerialization.data(withJSONObject: ["contentType": contentType, "byteLength": data.count])
        let reply = try await request(path: "api/v1/library/assets/upload", method: "POST", body: body, owner: owner)
        let reservation = try JSONDecoder().decode(Reservation.self, from: reply)
        var upload = URLRequest(url: reservation.uploadUrl); upload.httpMethod = "PUT"
        upload.httpBody = data; upload.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await urlSession.data(for: upload)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ZXCloudLibraryError.missingAsset }
        try await checkOwner(owner)
        var document = try load(owner); document.assetIDs[hash] = reservation.assetId; try save(document, owner: owner)
        return reservation.assetId
    }

    public func downloadPhoto(assetID: String, expectedOwner: String? = nil) async throws -> Data {
        let owner = try await scopedOwner(expectedOwner)
        guard UUID(uuidString: assetID) != nil else { throw ZXCloudLibraryError.missingAsset }
        struct Link: Decodable { let downloadUrl: URL }
        let reply = try await request(path: "api/v1/library/assets/\(assetID)", owner: owner)
        let link = try JSONDecoder().decode(Link.self, from: reply)
        let (data, response) = try await urlSession.data(from: link.downloadUrl)
        try await checkOwner(owner)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ZXCloudLibraryError.missingAsset }
        return data
    }

    private func request(path: String, method: String = "GET", body: Data? = nil, owner: String) async throws -> Data {
        let session = try await sessionProvider()
        guard session.userID == owner, !session.accessToken.isEmpty else { throw ZXCloudLibraryError.accountChanged }
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path) else { throw ZXCloudLibraryError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(app, forHTTPHeaderField: "x-zx-app")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await urlSession.data(for: request)
        try await checkOwner(owner)
        guard let http = response as? HTTPURLResponse else { throw ZXCloudLibraryError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ZXCloudLibraryError.http(http.statusCode, "sync request failed") }
        return data
    }
    private func scopedOwner(_ expected: String?) async throws -> String {
        let owner = try await currentOwner()
        guard expected == nil || expected?.lowercased() == owner.lowercased() else { throw ZXCloudLibraryError.accountChanged }
        return owner
    }
    private func checkOwner(_ owner: String) async throws {
        guard try await currentOwner() == owner else { throw ZXCloudLibraryError.accountChanged }
    }
    private func append(_ input: ZXCloudLibraryDraft, to document: inout Document) {
        var draft = input
        // Older clients only own fields they understand. Preserve newer metadata, including nested recipes.
        let original = document.pending.last(where: { $0.mutation.key == draft.key })?.mutation.payload
            ?? document.records[draft.key]?.payload ?? [:]
        draft.payload = Self.merge(original, with: draft.payload)
        // A revert while an earlier mutation is in flight still needs an acknowledgement of its own.
        if !document.pending.contains(where: { $0.mutation.key == draft.key }),
           let existing = document.records[draft.key], existing.payload == draft.payload,
           existing.contentRef == draft.contentRef, existing.deletedAt == draft.deletedAt,
           existing.updatedAt == draft.updatedAt { return }
        document.pending.removeAll { $0.mutation.key == draft.key && !$0.attempted }
        document.pending.append(.init(mutation: .init(draft: draft, revision: document.records[draft.key]?.revision ?? 0)))
    }
    private static func merge(_ original: [String: ZXJSONValue], with changed: [String: ZXJSONValue]) -> [String: ZXJSONValue] {
        var result = original
        for (key, value) in changed {
            if case .object(let old) = result[key], case .object(let new) = value { result[key] = .object(merge(old, with: new)) }
            else { result[key] = value }
        }
        return result
    }
    private func file(_ owner: String) -> URL {
        let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
    private func load(_ owner: String) throws -> Document {
        if let document = documents[owner] { return document }
        let url = file(owner)
        if !FileManager.default.fileExists(atPath: url.path) { return Document() }
        guard let data = try? Data(contentsOf: url), let document = try? JSONDecoder().decode(Document.self, from: data), document.schema == 1 else {
            throw ZXCloudLibraryError.corruptLocalState
        }
        documents[owner] = document
        return document
    }
    private func save(_ document: Document, owner: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: file(owner), options: .atomic)
        documents[owner] = document
    }
}
