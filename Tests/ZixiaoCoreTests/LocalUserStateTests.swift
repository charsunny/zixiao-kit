import XCTest
@testable import ZixiaoCore

final class LocalUserStateTests: XCTestCase {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let newYork = TimeZone(identifier: "America/New_York")!

    /// 上海时间某日某时。
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, tz: TimeZone? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz ?? shanghai
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: - 连续天数 (纯值)

    func testStreakCountsConsecutiveDays() {
        var s = ZXLocalUserSnapshot()
        XCTAssertTrue(s.recordOpen(at: date(2026, 9, 28), timeZone: shanghai))
        XCTAssertFalse(s.recordOpen(at: date(2026, 9, 28, 22), timeZone: shanghai), "同一天第二次不算")
        XCTAssertTrue(s.recordOpen(at: date(2026, 9, 29, 8), timeZone: shanghai))
        XCTAssertTrue(s.recordOpen(at: date(2026, 9, 30), timeZone: shanghai))
        XCTAssertEqual(s.streak, 3)
        XCTAssertEqual(s.totalDays, 3)
        XCTAssertEqual(s.firstOpenedDay, "2026-09-28")
        XCTAssertEqual(s.lastOpenedDay, "2026-09-30")

        // 断一天: 重来。
        s.recordOpen(at: date(2026, 10, 2), timeZone: shanghai)
        XCTAssertEqual(s.streak, 1)
        XCTAssertEqual(s.longestStreak, 3)
        XCTAssertEqual(s.totalDays, 4)
    }

    func testStreakAcrossMonthAndYearBoundaries() {
        var s = ZXLocalUserSnapshot()
        s.recordOpen(at: date(2026, 12, 31), timeZone: shanghai)
        s.recordOpen(at: date(2027, 1, 1), timeZone: shanghai)
        s.recordOpen(at: date(2027, 1, 2), timeZone: shanghai)
        XCTAssertEqual(s.streak, 3)
    }

    func testDayBoundaryFollowsGivenTimeZone() {
        // 纽约 9 月 28 日 23:30 = 上海 9 月 29 日 11:30。
        let instant = date(2026, 9, 28, 23, tz: newYork).addingTimeInterval(30 * 60)
        XCTAssertEqual(ZXLocalUserSnapshot.dayKey(for: instant, timeZone: newYork), "2026-09-28")
        XCTAssertEqual(ZXLocalUserSnapshot.dayKey(for: instant, timeZone: shanghai), "2026-09-29")
    }

    func testStreakAcrossDaylightSavingChange() {
        // 纽约 2026-11-01 回拨一小时, 那天有 25 小时, 不能被算成断签或两天。
        var s = ZXLocalUserSnapshot()
        s.recordOpen(at: date(2026, 10, 31, 20, tz: newYork), timeZone: newYork)
        s.recordOpen(at: date(2026, 11, 1, 20, tz: newYork), timeZone: newYork)
        s.recordOpen(at: date(2026, 11, 2, 8, tz: newYork), timeZone: newYork)
        XCTAssertEqual(s.streak, 3)
    }

    func testClockGoingBackwardsDoesNotBreakStreak() {
        var s = ZXLocalUserSnapshot()
        s.recordOpen(at: date(2026, 9, 28), timeZone: shanghai)
        s.recordOpen(at: date(2026, 9, 29), timeZone: shanghai)
        XCTAssertFalse(s.recordOpen(at: date(2026, 9, 27), timeZone: shanghai))
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.lastOpenedDay, "2026-09-29")
    }

    func testCurrentStreakDecaysWhenMissed() {
        var s = ZXLocalUserSnapshot()
        s.recordOpen(at: date(2026, 9, 28), timeZone: shanghai)
        s.recordOpen(at: date(2026, 9, 29), timeZone: shanghai)
        XCTAssertEqual(s.currentStreak(asOf: date(2026, 9, 29, 23), timeZone: shanghai), 2)
        XCTAssertEqual(s.currentStreak(asOf: date(2026, 9, 30), timeZone: shanghai), 2, "今天还没开, 昨天的仍算数")
        XCTAssertEqual(s.currentStreak(asOf: date(2026, 10, 1), timeZone: shanghai), 0)
    }

    // MARK: - 最近打开与偏好

    func testRecentDedupesAndCaps() {
        var s = ZXLocalUserSnapshot()
        for i in 0..<25 {
            s.noteOpened(ZXRecentItem(kind: "book", itemId: "b\(i)", openedAt: Date(timeIntervalSince1970: Double(i))))
        }
        s.noteOpened(ZXRecentItem(kind: "book", itemId: "b10", title: "论语", openedAt: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(s.recent.count, ZXLocalUserSnapshot.recentLimit)
        XCTAssertEqual(s.recent.first?.id, "book:b10")
        XCTAssertEqual(s.recent.filter { $0.itemId == "b10" }.count, 1)
        // 同 id 不同 kind 是两样东西。
        s.noteOpened(ZXRecentItem(kind: "hexagram", itemId: "b10"))
        XCTAssertEqual(s.recent.filter { $0.itemId == "b10" }.count, 2)
    }

    func testFlagsDefaultOffAndScopeSeparation() {
        var s = ZXLocalUserSnapshot()
        XCTAssertEqual(ZXPreferenceKey.liZhu.scope, .device)
        XCTAssertEqual(("reminder" as ZXPreferenceKey).scope, .user, "字面量默认账号级")
        XCTAssertFalse(s.flag(.liZhu))
        XCTAssertTrue(s.flag("unknown", default: true))
        s.setFlag(.liZhu, true)
        s.setFlag("reminder", true)
        XCTAssertTrue(s.flag(.liZhu))
        XCTAssertEqual(s.deviceFlags, ["lizhu": true])
        XCTAssertEqual(s.flags, ["reminder": true])
        XCTAssertEqual(s.devicePortion, ZXLocalUserSnapshot(deviceFlags: ["lizhu": true]))
    }

    func testDecodingToleratesMissingFields() throws {
        let old = #"{"schema":1,"streak":3,"flags":{"a":true}}"#
        let s = try JSONDecoder().decode(ZXLocalUserSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(s.streak, 3)
        XCTAssertEqual(s.flags, ["a": true])
        XCTAssertEqual(s.deviceFlags, [:])
        XCTAssertEqual(s.recent, [])
    }

    // MARK: - 持久化 (actor)

    func testStorePersistsPerUser() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ZXLocalUserState(directory: dir)
        try await store.recordOpen(for: "User-A", at: date(2026, 9, 29), timeZone: shanghai)
        try await store.setFlag("reminder", true, for: "User-A")
        try await store.noteOpened(ZXRecentItem(kind: "book", itemId: "lunyu", title: "论语",
                                                openedAt: Date(timeIntervalSince1970: 1_790_000_000.123)),
                                   for: "User-A")

        // 新实例从盘上读。
        let reopened = ZXLocalUserState(directory: dir)
        let a = await reopened.snapshot(for: "user-a")   // 大小写不敏感
        XCTAssertEqual(a.streak, 1)
        XCTAssertTrue(a.flag("reminder"))
        XCTAssertEqual(a.recent.first?.title, "论语")
        XCTAssertEqual(a.recent.first?.openedAt.timeIntervalSince1970 ?? 0, 1_790_000_000.123, accuracy: 0.001)

        // 另一个用户看不到。
        let b = await reopened.snapshot(for: "user-b")
        XCTAssertEqual(b, .empty)
        let reminderForB = await reopened.flag("reminder", for: "user-b")
        XCTAssertFalse(reminderForB)
    }

    func testSavedEqualsReloaded() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ZXLocalUserState(directory: dir)
        let saved = try await store.recordOpen(for: "u", at: Date(timeIntervalSince1970: 1_790_000_000.123456))
        let reloaded = await ZXLocalUserState(directory: dir).snapshot(for: "u")
        XCTAssertEqual(saved, reloaded, "内存里那份必须与重启后读回的相等")
    }

    func testAdoptDeviceStateMergesAndRemovesDeviceCopy() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ZXLocalUserState(directory: dir)
        // 首启离线: 记在设备名下。
        try await store.recordOpen(for: nil, at: date(2026, 9, 27), timeZone: shanghai)
        try await store.recordOpen(for: nil, at: date(2026, 9, 28), timeZone: shanghai)
        try await store.setFlag("night", true, for: nil)
        try await store.setFlag("reminder", true, for: nil)
        try await store.setFlag("reminder", false, for: "u1")
        try await store.setFlag(.liZhu, true, for: nil)

        try await store.adoptDeviceState(into: "u1")
        let merged = await store.snapshot(for: "u1")
        XCTAssertEqual(merged.streak, 2)
        XCTAssertEqual(merged.firstOpenedDay, "2026-09-27")
        XCTAssertTrue(merged.flag("night"))
        XCTAssertEqual(merged.flags["reminder"], false, "账号自己的值优先")
        XCTAssertEqual(merged.deviceFlags, [:], "设备级开关不并进账号")

        let device = await store.snapshot(for: nil)
        XCTAssertEqual(device, ZXLocalUserSnapshot(deviceFlags: ["lizhu": true]), "设备名下只剩设备偏好")
        // 再并一次是空操作。
        try await store.adoptDeviceState(into: "u2")
        let other = await store.snapshot(for: "u2")
        XCTAssertEqual(other, .empty)
    }

    func testLiZhuIsDeviceScoped() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ZXLocalUserState(directory: dir)
        try await store.setFlag(.liZhu, true, for: "u1")

        // 不随 userId: 别的用户、未登录都看得到同一个值。
        for user in ["u1", "u2", nil] as [String?] {
            let on = await store.flag(.liZhu, for: user)
            XCTAssertTrue(on)
        }
        let direct = await store.deviceFlag(.liZhu)
        XCTAssertTrue(direct)
        // 存在 device 文件里, u1 的文件里没有。
        let u1 = await store.snapshot(for: "u1")
        XCTAssertEqual(u1, .empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("device.json").path))

        // 删号 / 退出 / 清设备名下账号级态, 都不清它。
        try await store.remove(for: "u1")
        try await store.remove(for: nil)
        let reopened = ZXLocalUserState(directory: dir)
        let still = await reopened.flag(.liZhu, for: "u3")
        XCTAssertTrue(still)
    }

    func testRemoveDeletesFile() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ZXLocalUserState(directory: dir)
        try await store.setFlag("reminder", true, for: "u1")
        try await store.remove(for: "u1")
        let s = await ZXLocalUserState(directory: dir).snapshot(for: "u1")
        XCTAssertEqual(s, .empty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.isEmpty)
    }

    func testUserIdIsSanitizedForFileNames() {
        XCTAssertEqual(ZXLocalUserState.key(for: nil), "device")
        XCTAssertEqual(ZXLocalUserState.key(for: ""), "device")
        XCTAssertEqual(ZXLocalUserState.key(for: "../../etc"), "u-______etc")
        XCTAssertEqual(ZXLocalUserState.key(for: "ABC-def"), "u-abc-def")
    }
}

final class AppleNonceTests: XCTestCase {
    func testNonceShape() {
        let a = ZXAppleNonce.make()
        let b = ZXAppleNonce.make()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        let allowed = Set(ZXAppleNonce.charset)
        XCTAssertTrue(a.allSatisfy(allowed.contains))
        XCTAssertEqual(ZXAppleNonce.make(length: 64).count, 64)
        XCTAssertEqual(ZXAppleNonce.charset.count, 65)
    }

    func testSha256MatchesKnownVector() {
        XCTAssertEqual(ZXAppleNonce.sha256("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
