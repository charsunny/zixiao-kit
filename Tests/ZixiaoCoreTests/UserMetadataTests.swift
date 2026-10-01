import XCTest
@testable import ZixiaoCore

/// T44: 昵称 / 头像样式 (user_metadata) 的解析、空值回落, 以及 `ZXAuth.updateProfile` 与错误原文透传。
final class UserMetadataTests: XCTestCase {
    // MARK: - 解析

    func testDisplayNameReadsDisplayNameKey() {
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["display_name": "  子房 \n"]), "子房")
    }

    func testDisplayNameFallsBackToFullNameThenName() {
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["full_name": "张良", "name": "zl"]), "张良")
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["name": "zl"]), "zl")
        // display_name 为空白 / null / 非字符串: 视同没有, 继续回落。
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["display_name": "   ", "full_name": "张良"]), "张良")
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["display_name": nil, "name": "zl"]), "zl")
        XCTAssertEqual(ZXUserMetadata.displayName(in: ["display_name": 42, "name": "zl"]), "zl")
    }

    func testDisplayNameEmptyMetadataIsNil() {
        XCTAssertNil(ZXUserMetadata.displayName(in: [:]))
        XCTAssertNil(ZXUserMetadata.displayName(in: ["display_name": "", "full_name": " ", "name": nil]))
    }

    func testAvatarStyleAcceptsIntegralForms() {
        XCTAssertEqual(ZXUserMetadata.avatarStyle(in: ["avatar_style": 3]), 3)
        XCTAssertEqual(ZXUserMetadata.avatarStyle(in: ["avatar_style": 2.0]), 2)
        XCTAssertEqual(ZXUserMetadata.avatarStyle(in: ["avatar_style": " 4 "]), 4)
        XCTAssertEqual(ZXUserMetadata.avatarStyle(in: ["avatar_style": 0]), 0)
    }

    func testAvatarStyleRejectsGarbage() {
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: [:]))
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: ["avatar_style": nil]))
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: ["avatar_style": -1]))
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: ["avatar_style": 2.5]))
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: ["avatar_style": "方印"]))
        XCTAssertNil(ZXUserMetadata.avatarStyle(in: ["avatar_style": true]))
    }

    func testUserInitFromMetadata() {
        let user = ZXAuthUser(id: "ABC", isAnonymous: false, providers: [.apple],
                              metadata: ["display_name": " 玄友 ", "avatar_style": 2, "other": "x"])
        XCTAssertEqual(user.id, "abc")
        XCTAssertEqual(user.displayName, "玄友")
        XCTAssertEqual(user.avatarStyle, 2)

        let bare = ZXAuthUser(id: "abc", isAnonymous: true, metadata: [:])
        XCTAssertNil(bare.displayName)
        XCTAssertNil(bare.avatarStyle)

        // 直接构造也规范化: 空白昵称与负样式记为 nil。
        let odd = ZXAuthUser(id: "abc", isAnonymous: false, displayName: "  ", avatarStyle: -3)
        XCTAssertNil(odd.displayName)
        XCTAssertNil(odd.avatarStyle)
    }

    func testOldEncodedUserDecodesWithoutProfileFields() throws {
        // 升级前持久化的 ZXAuthUser (没有新字段) 照样解得开。
        let json = #"{"id":"abc","isAnonymous":false,"providers":["phone"],"phone":"+8613800001234"}"#
        let user = try JSONDecoder().decode(ZXAuthUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.providers, [.phone])
        XCTAssertNil(user.displayName)
        XCTAssertNil(user.avatarStyle)
    }

    // MARK: - patch

    func testPatchShapes() {
        XCTAssertEqual(ZXUserMetadata.patch(displayName: nil, avatarStyle: nil), [:])
        XCTAssertEqual(ZXUserMetadata.patch(displayName: " 子房 ", avatarStyle: nil), ["display_name": "子房"])
        // 清空昵称写 null (GoTrue 删键), 界面回落默认名。
        XCTAssertEqual(ZXUserMetadata.patch(displayName: "  ", avatarStyle: nil), ["display_name": nil])
        XCTAssertEqual(ZXUserMetadata.patch(displayName: nil, avatarStyle: 4), ["avatar_style": 4])
        XCTAssertEqual(ZXUserMetadata.patch(displayName: nil, avatarStyle: -2), ["avatar_style": 0])
    }

    // MARK: - ZXAuth.updateProfile

    @MainActor
    func testUpdateProfileWritesMetadataAndKeepsUserId() async throws {
        let linked = ZXAuthUser(id: "bbbbbbbb-0000-0000-0000-000000000002", isAnonymous: false, providers: [.apple])
        let backend = MockAuthBackend(stored: linked)
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        XCTAssertNil(auth.user?.displayName)

        try await auth.updateProfile(displayName: "  子房 ", avatarStyle: 3)
        XCTAssertEqual(backend.lastMetadataPatch, ["display_name": "子房", "avatar_style": 3])
        XCTAssertEqual(auth.user?.displayName, "子房")
        XCTAssertEqual(auth.user?.avatarStyle, 3)
        XCTAssertEqual(auth.userId, linked.id)

        try await auth.updateDisplayName("")
        XCTAssertNil(auth.user?.displayName, "清空昵称回落默认")
        XCTAssertEqual(auth.user?.avatarStyle, 3, "只改昵称不动样式")

        try await auth.updateAvatarStyle(1)
        XCTAssertEqual(auth.user?.avatarStyle, 1)
    }

    @MainActor
    func testUpdateProfileNoopDoesNotCallBackend() async throws {
        let backend = MockAuthBackend(stored: ZXAuthUser(id: "abc", isAnonymous: false, providers: [.phone]))
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        try await auth.updateProfile()
        XCTAssertEqual(backend.count("updateUserMetadata"), 0)
    }

    @MainActor
    func testUpdateProfileRequiresUserAndBackend() async {
        let offline = ZXAuth(backend: MockAuthBackend(configured: false))
        do {
            try await offline.updateDisplayName("子房")
            XCTFail("离线应抛错")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .offline)
        }
    }

    // MARK: - 底层原文透传

    @MainActor
    func testBackendFailureDetailIsKept() async {
        let backend = MockAuthBackend()
        backend.linkAppleFailure = ZXAuthFailure(
            .providerDisabled,
            detail: "Unsupported provider: provider is not enabled (validation_failed · HTTP 400)")
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.linkApple(idToken: "t", nonce: "n")
            XCTFail("应抛错")
        } catch {
            // 对外类型不变: 仍是 ZXCoreError。
            XCTAssertEqual(error as? ZXCoreError, .providerDisabled)
            XCTAssertEqual(ZXCoreError(error), .providerDisabled)
        }
        XCTAssertEqual(auth.lastErrorDetail, "Unsupported provider: provider is not enabled (validation_failed · HTTP 400)")

        // 下一次操作开始即清空; 我们自己的错误没有更多原文。
        do { try await auth.sendPhoneOTP("abc") } catch {}
        XCTAssertNil(auth.lastErrorDetail)
    }

    @MainActor
    func testUpdateFailureDetailIsKept() async {
        let backend = MockAuthBackend(stored: ZXAuthUser(id: "abc", isAnonymous: false, providers: [.phone]))
        backend.updateMetadataError = ZXAuthFailure(.backend("JWT expired"), detail: "JWT expired (bad_jwt · HTTP 401)")
        let auth = ZXAuth(backend: backend)
        await auth.bootstrap()
        do {
            try await auth.updateDisplayName("子房")
            XCTFail("应抛错")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .backend("JWT expired"))
        }
        XCTAssertEqual(auth.lastErrorDetail, "JWT expired (bad_jwt · HTTP 401)")
        XCTAssertNil(auth.user?.displayName)
    }

    func testCoreErrorUnwrapsFailure() {
        XCTAssertEqual(ZXCoreError(ZXAuthFailure(.rateLimited, detail: "x")), .rateLimited)
    }

    func testDefaultBackendImplementationRefuses() async {
        struct Legacy: ZXAuthBackend {
            var isConfigured: Bool { true }
            func restoreSession() async throws -> ZXAuthUser? { nil }
            func signInAnonymously() async throws -> ZXAuthUser { ZXAuthUser(id: "a", isAnonymous: true) }
            func linkApple(idToken: String, nonce: String) async throws -> ZXAuthUser { throw ZXCoreError.cancelled }
            func requestPhoneLink(phone: String) async throws {}
            func verifyPhoneLink(phone: String, code: String) async throws -> ZXAuthUser { throw ZXCoreError.cancelled }
            func signInWithApple(idToken: String, nonce: String) async throws -> ZXAuthUser { throw ZXCoreError.cancelled }
            func requestPhoneSignIn(phone: String) async throws {}
            func verifyPhoneSignIn(phone: String, code: String) async throws -> ZXAuthUser { throw ZXCoreError.cancelled }
            func signOut() async throws {}
            func deleteAccount() async throws {}
        }
        do {
            _ = try await Legacy().updateUserMetadata(["display_name": "x"])
            XCTFail("默认实现应拒绝")
        } catch {
            XCTAssertEqual(error as? ZXCoreError, .providerDisabled)
        }
    }
}
