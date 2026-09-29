//  ZXVerticalForms.swift — 直排标点
//
//  横排的「，」「。」在竖排里要换成直排形 (U+FE10 一带), 落在字的正下方而不是右下角。
//  映射表与 Flutter 版 `vertical_forms.dart` 逐项一致, 两端竖排出来的标点才长得一样。
//  随包思源宋体子集覆盖了表里全部直排形 (实测 cmap)。

public enum ZXVerticalForms: Sendable {
    /// 横排标点 → 直排形。
    public static let map: [Character: Character] = [
        "，": "︐",
        "。": "︒",
        "、": "︑",
        "：": "︓",
        "；": "︔",
        "！": "︕",
        "？": "︖",
        "「": "﹁",
        "」": "﹂",
        "『": "﹃",
        "』": "﹄",
        "“": "﹁",
        "”": "﹂",
        "‘": "﹃",
        "’": "﹄",
        "（": "︵",
        "）": "︶",
        "《": "︽",
        "》": "︾",
        "〈": "︿",
        "〉": "﹀",
        "—": "｜",
        "…": "︙",
    ]

    /// 单个字的直排形; 不在表里的原样返回。
    public static func vertical(_ ch: Character) -> Character {
        map[ch] ?? ch
    }

    /// 整段转直排形。
    public static func convert(_ text: String) -> String {
        String(text.map(vertical))
    }

    /// 是不是标点。标点不能居列首 (避头), 排到列尾放不下时允许挤在列尾。
    /// 直排形本身也算 —— 调用方可能已经转过一遍。
    public static func isPunctuation(_ ch: Character) -> Bool {
        map[ch] != nil || verticalForms.contains(ch) || ch == "·" || ch == "‧"
    }

    private static let verticalForms: Set<Character> = Set(map.values)
}
