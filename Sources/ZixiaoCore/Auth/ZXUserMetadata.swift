import Foundation

/// 用户自填的资料 (昵称、头像样式) 存在 GoTrue 的 `auth.users.user_metadata` 里 —— 不另建资料表:
/// 只有两三个小字段, 跟着 session 一起下发, 离线时钥匙串里那份 session 也带着, 不用额外请求。
///
/// 这里只做与 Supabase 无关的纯解析 / 组装 (`ZXJSONValue`), 便于单测; 与 `AnyJSON` 的互转在
/// `ZXSupabaseAuthBackend`。
///
/// 键名 (矩阵内各 App 共用同一个 GoTrue 时也通用):
/// - `display_name`: String, 昵称。缺省时回落到 OAuth 提供方写的 `full_name` / `name`。
/// - `avatar_style`: Int (≥ 0), 程序化头像的样式序号; 各 App 自己解释序号, 认不出的按默认样式画。
/// - `zx_apple_linked`: Bool, 这个账号经子晓系「Apple 换 session」登录过 (见 `ZXAppleExchange`)。
///   服务端签的代理登录用户在 GoTrue 里没有 Apple identity, 靠这一笔让「绑定方式」认得出 Apple。
public enum ZXUserMetadata {
    public static let displayNameKey = "display_name"
    public static let avatarStyleKey = "avatar_style"
    public static let appleLinkedKey = "zx_apple_linked"
    /// `display_name` 缺省时依次回落的键 (GoTrue 的 OAuth 提供方会写这两个)。
    public static let fallbackNameKeys = ["full_name", "name"]

    /// 昵称: `display_name` → `full_name` → `name`, 取第一个规范化后非空的字符串。都没有返回 nil (界面用默认名)。
    public static func displayName(in metadata: [String: ZXJSONValue]) -> String? {
        for key in [displayNameKey] + fallbackNameKeys {
            if case .string(let raw)? = metadata[key], let name = normalizedName(raw) {
                return name
            }
        }
        return nil
    }

    /// 头像样式序号。接受整数、整值的浮点 (JSON 往返可能变成 2.0)、纯数字字符串; 负数与其它一律 nil。
    public static func avatarStyle(in metadata: [String: ZXJSONValue]) -> Int? {
        let value: Int?
        switch metadata[avatarStyleKey] {
        case .int(let v)?: value = v
        case .double(let v)? where v.rounded() == v && abs(v) < 1_000_000: value = Int(v)
        case .string(let s)?: value = Int(s.trimmingCharacters(in: .whitespaces))
        default: value = nil
        }
        guard let value, value >= 0 else { return nil }
        return value
    }

    /// 去首尾空白与换行; 空串返回 nil。长度限制是界面的事 (各 App 不同), 这里不截。
    public static func normalizedName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 组一次 `PUT /user` 的 `data` (GoTrue 按顶层键合并进 user_metadata, 值为 null 则删除该键)。
    /// - Parameters:
    ///   - displayName: nil = 不动; 规范化后为空 = 清掉 (`null`, 界面回落默认名)。
    ///   - avatarStyle: nil = 不动; 负数按 0 记。
    public static func patch(displayName: String?, avatarStyle: Int?) -> [String: ZXJSONValue] {
        var data: [String: ZXJSONValue] = [:]
        if let displayName {
            data[displayNameKey] = normalizedName(displayName).map(ZXJSONValue.string) ?? .null
        }
        if let avatarStyle {
            data[avatarStyleKey] = .int(max(0, avatarStyle))
        }
        return data
    }

    /// 把一次 patch 合到已有的用户上 (mock 后端、预览后端用; 真后端以服务端返回的为准)。
    public static func applying(_ patch: [String: ZXJSONValue], to user: ZXAuthUser) -> ZXAuthUser {
        var user = user
        if let name = patch[displayNameKey] {
            if case .string(let raw) = name { user.displayName = normalizedName(raw) } else { user.displayName = nil }
        }
        if patch[avatarStyleKey] != nil {
            user.avatarStyle = avatarStyle(in: patch)
        }
        return user
    }
}
