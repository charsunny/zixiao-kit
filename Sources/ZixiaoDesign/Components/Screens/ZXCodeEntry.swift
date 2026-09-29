//  ZXCodeEntry.swift — 验证码输入
//
//  六个格子只是画出来的; 真正接收输入的是一个铺在格子上、看不见的 TextField。
//  为什么不六个 TextField: 系统短信验证码自动填充 (`.oneTimeCode`) 与粘贴都是往**一个**
//  输入框里塞整串, 拆成六个就得自己在框之间搬字, 回删、光标、VoiceOver 全都要重写。
//
//  输入规则抽成纯 struct `ZXCodeEntryState`, 不依赖 SwiftUI, 测试直接驱动它。

import SwiftUI

/// 验证码所处的阶段。由调用方驱动: `onComplete` 里设为 `.verifying`, 服务端答复后设为
/// `.failed` 或 `.succeeded`。
///
/// 每次校验都请经过 `.verifying`: 视图靠「阶段变了」触发抖动 / 点亮, 连续两次
/// 从 `.failed` 设到 `.failed` 不算变化。
public enum ZXCodeEntryPhase: Sendable, Hashable {
    /// 可输入。
    case editing
    /// 已输满, 等待校验。输入锁住。
    case verifying
    /// 校验失败: 抖动、清空, 之后可重新输入。
    case failed
    /// 校验通过: 格子依次点亮, 输入锁住。
    case succeeded
}

/// 状态机吐出的事件, 视图据此做一次性的动作 (回调、抖动、触觉)。
public enum ZXCodeEntryEvent: Sendable, Hashable {
    /// 刚好输满 (从不满到满的那一下)。
    case completed(String)
    /// 进入失败: 码已清空。
    case rejected
    /// 进入成功。
    case accepted
}

/// 验证码输入的纯状态机。
public struct ZXCodeEntryState: Sendable, Hashable {
    public let length: Int
    public private(set) var code: String
    public private(set) var phase: ZXCodeEntryPhase
    /// 最近一次被拒的码。清空之后仍留着它, 让视图在抖动时还能把错的那串画出来 (朱色),
    /// 用户看得见「哪串错了」; 下一次输入即清掉。
    public private(set) var rejected: String?

    public init(length: Int = 6, code: String = "", phase: ZXCodeEntryPhase = .editing) {
        self.length = max(length, 1)
        self.code = Self.sanitize(code, length: max(length, 1))
        self.phase = phase
    }

    /// 一个格子画什么。
    public enum Cell: Sendable, Hashable {
        case filled(Character)
        /// 下一个要填的格子 (画闪烁的光标)。
        case cursor
        case empty
    }

    public var isComplete: Bool { code.count == length }

    /// 校验中与成功后锁住输入: 此时再改码, 回调出去的那串就与屏幕上的不一致了。
    public var acceptsInput: Bool { phase == .editing || phase == .failed }

    /// 光标所在格; 输满或锁住时没有光标。
    public var cursorIndex: Int? { acceptsInput && !isComplete ? code.count : nil }

    public func cell(at index: Int) -> Cell {
        let chars = Array(code)
        if index < chars.count { return .filled(chars[index]) }
        return index == cursorIndex ? .cursor : .empty
    }

    /// 只留数字, 截到 `length` 位。
    ///
    /// 只认十进制数字 (Unicode Nd), 再落成 ASCII: 粘贴进来的全角「１２３」、短信整段
    /// 「验证码 123456, 5 分钟内有效」都能得到正确的码 (只取前 length 位, 后面的「5」截掉)。
    /// 不用 `isNumber`: 它把「五」「½」也算数字, 短信里的「五分钟」会混进码里。
    public static func sanitize(_ raw: String, length: Int) -> String {
        var out = ""
        for ch in raw {
            guard ch.unicodeScalars.count == 1,
                  let scalar = ch.unicodeScalars.first,
                  CharacterSet.decimalDigits.contains(scalar),
                  let v = ch.wholeNumberValue, (0...9).contains(v)
            else { continue }
            out.append(Character(String(v)))
            if out.count == length { break }
        }
        return out
    }

    /// 输入框的文字变了 (打字、回删、粘贴、自动填充都走这里)。
    ///
    /// - Returns: 从不满到满时返回 `.completed`。锁住时忽略输入, 返回 nil。
    @discardableResult
    public mutating func update(text: String) -> ZXCodeEntryEvent? {
        guard acceptsInput else { return nil }
        let new = Self.sanitize(text, length: length)
        guard new != code else { return nil }
        let wasComplete = isComplete
        code = new
        rejected = nil
        // 失败后重新动手 = 回到编辑; 否则调用方下一次设 `.failed` 时视图看不出变化。
        if phase == .failed { phase = .editing }
        return isComplete && !wasComplete ? .completed(code) : nil
    }

    /// 回删一位。
    @discardableResult
    public mutating func deleteBackward() -> ZXCodeEntryEvent? {
        update(text: String(code.dropLast()))
    }

    /// 调用方推进阶段。
    @discardableResult
    public mutating func transition(to newPhase: ZXCodeEntryPhase) -> ZXCodeEntryEvent? {
        guard newPhase != phase else { return nil }
        phase = newPhase
        switch newPhase {
        case .failed:
            // 失败即清空: 错码留在格子里, 用户得先删六下才能重输。
            rejected = code
            code = ""
            return .rejected
        case .succeeded:
            return .accepted
        case .editing, .verifying:
            return nil
        }
    }
}

// MARK: - 视图

public struct ZXCodeEntry: View {
    @Binding var code: String
    let phase: ZXCodeEntryPhase
    let onComplete: @MainActor (String) -> Void

    @State private var state: ZXCodeEntryState
    @State private var text = ""
    @State private var shakes = 0
    @State private var showsRejected = false
    @FocusState private var focused: Bool
    @Environment(\.zxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 格子尺寸是这个控件的固有几何 (不是间距), 按手指与数字字号定。
    private let cellHeight: CGFloat = 56
    private let cellMaxWidth: CGFloat = 52
    private let cursorHeight: CGFloat = 24
    private let cursorWidth: CGFloat = 2
    /// 当前格的描边粗细: 比发丝线粗, 光标闪灭的间隙里也看得出「在这一格」。
    private let activeBorder: CGFloat = 1.5
    /// 抖动时长与成功点亮时每格的间隔。
    private let shakeDuration: Double = 0.45
    private let lightStagger: Double = 0.06

    /// - Parameters:
    ///   - length: 位数。
    ///   - code: 当前的码 (双向: 调用方清空它, 格子也清空)。
    ///   - phase: 阶段, 见 `ZXCodeEntryPhase`。
    ///   - onComplete: 输满时调一次。调用方在这里把 phase 设为 `.verifying` 并发起校验。
    public init(length: Int = 6, code: Binding<String>, phase: ZXCodeEntryPhase,
                onComplete: @escaping @MainActor (String) -> Void) {
        _code = code
        self.phase = phase
        self.onComplete = onComplete
        let initial = ZXCodeEntryState(length: length, code: code.wrappedValue, phase: phase)
        _state = State(initialValue: initial)
        _text = State(initialValue: initial.code)
    }

    public var body: some View {
        ZStack {
            HStack(spacing: theme.space.sm) {
                ForEach(0..<state.length, id: \.self) { index in
                    cell(index)
                }
            }
            .modifier(ZXShakeEffect(progress: CGFloat(shakes)))
            .animation(theme.motion.adapted(theme.motion.bouncy, reduceMotion: reduceMotion), value: state.code)
            .accessibilityHidden(true)

            TextField("", text: $text)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .focused($focused)
                // 字与光标都透明: 看得见的是下面画的格子; 框本身仍铺满整行, 点哪里都能聚焦,
                // VoiceOver 也能找到它。
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: cellHeight)
                .disabled(!state.acceptsInput)
                .accessibilityLabel("验证码")
                .accessibilityValue("已输入 \(state.code.count) 位, 共 \(state.length) 位")
                .accessibilityIdentifier("zx.codeEntry.field")
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = state.acceptsInput }
        .onChange(of: text) { _, new in handleInput(new) }
        .onChange(of: code) { _, new in
            // 调用方改了码 (通常是清空重来)。这不是用户输入, 不触发完成回调。
            guard new != state.code else { return }
            _ = state.update(text: new)
            text = state.code
        }
        .onChange(of: phase) { _, new in handlePhase(new) }
        .task(id: shakes) {
            // 错码朱色停留一会儿再淡去: 抖动的那一下看得见错在哪, 之后回到空格子。
            guard shakes > 0 else { return }
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(theme.motion.adapted(theme.motion.standard, reduceMotion: reduceMotion)) {
                showsRejected = false
            }
        }
        .sensoryFeedback(.error, trigger: shakes) { _, new in new > 0 }
        .sensoryFeedback(.success, trigger: phase) { _, new in new == .succeeded }
    }

    private func handleInput(_ new: String) {
        let event = state.update(text: new)
        if text != state.code { text = state.code }
        if code != state.code { code = state.code }
        if state.rejected == nil { showsRejected = false }
        if case .completed(let value) = event { onComplete(value) }
    }

    private func handlePhase(_ new: ZXCodeEntryPhase) {
        switch state.transition(to: new) {
        case .rejected:
            text = ""
            code = ""
            showsRejected = true
            if reduceMotion {
                shakes += 1
            } else {
                withAnimation(.linear(duration: shakeDuration)) { shakes += 1 }
            }
            focused = true
        case .accepted:
            focused = false
        default:
            break
        }
    }

    // MARK: 格子

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let lit = state.phase == .succeeded
        let rejectedChars = Array(state.rejected ?? "")
        let showingRejected = showsRejected && state.code.isEmpty && index < rejectedChars.count
        let shape = RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)

        ZStack {
            shape.fill(lit ? theme.color.accent : theme.color.fill)
            shape.stroke(borderColor(index: index, showingRejected: showingRejected),
                         lineWidth: state.cursorIndex == index ? activeBorder : ZXMetric.hairline)

            if showingRejected {
                Text(String(rejectedChars[index]))
                    .font(theme.type.numeral(28, relativeTo: .title))
                    .foregroundStyle(theme.color.danger)
                    .transition(.opacity)
            } else {
                switch state.cell(at: index) {
                case .filled(let ch):
                    Text(String(ch))
                        .font(theme.type.numeral(28, relativeTo: .title))
                        .foregroundStyle(lit ? theme.color.accentOn : theme.color.textPrimary)
                        // 数字从上方轻轻落进格子。id 带上数字本身: 同一格换了数字也重新落一次。
                        .id("\(index)-\(ch)")
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.6).combined(with: .offset(y: -8)).combined(with: .opacity),
                            removal: .opacity))
                case .cursor:
                    ZXBlinkingCursor(height: cursorHeight, width: cursorWidth, still: reduceMotion || !focused)
                case .empty:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: cellMaxWidth)
        .frame(height: cellHeight)
        // 成功时依次点亮: 每格晚一点, 像一排灯从左到右亮起。减少动态下一齐亮。
        .animation(theme.motion.adapted(theme.motion.smooth, reduceMotion: reduceMotion)
                    .delay(reduceMotion ? 0 : Double(index) * lightStagger),
                   value: lit)
    }

    private func borderColor(index: Int, showingRejected: Bool) -> Color {
        if showingRejected { return theme.color.danger }
        if state.cursorIndex == index && focused { return theme.color.accent }
        return theme.color.separator
    }
}

/// 闪烁的光标。用 TimelineView 按时钟算亮灭, 不用 repeatForever 动画:
/// 后者一旦开始就停不下来, 格子重建时还会叠出第二个循环。
private struct ZXBlinkingCursor: View {
    let height: CGFloat
    let width: CGFloat
    let still: Bool
    @Environment(\.zxTheme) private var theme

    /// 系统光标的闪烁周期约 1 秒, 亮灭各半。
    private let halfPeriod: Double = 0.53

    var body: some View {
        TimelineView(.periodic(from: .now, by: halfPeriod)) { context in
            let on = still || Int(context.date.timeIntervalSinceReferenceDate / halfPeriod) % 2 == 0
            Capsule()
                .fill(theme.color.accent)
                .frame(width: width, height: height)
                .opacity(on ? 1 : 0)
        }
    }
}

/// 左右摆三下、逐渐收住的抖动。`progress` 每 +1 抖一轮。
private struct ZXShakeEffect: GeometryEffect {
    var progress: CGFloat
    /// 最大摆幅。是动效的幅度, 不是版面间距, 所以不走 space token。
    private let travel: CGFloat = 8

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = progress - progress.rounded(.down)
        let x = travel * sin(t * .pi * 6) * (1 - t)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

// MARK: - 重发倒计时

/// 「59 秒后可重新发送」→ 到点变成一个按钮。
public struct ZXResendCountdown: View {
    let seconds: Int
    let title: String
    let onResend: @MainActor () -> Void

    @State private var deadline: Date
    @Environment(\.zxTheme) private var theme

    /// - Parameters:
    ///   - seconds: 冷却秒数。视图出现时即开始倒数 (验证码刚发出)。
    ///   - title: 按钮字。倒计时文案是「N 秒后可」+ title。
    public init(seconds: Int = 60, title: String = "重新发送", onResend: @escaping @MainActor () -> Void) {
        self.seconds = seconds
        self.title = title
        self.onResend = onResend
        _deadline = State(initialValue: Date.now.addingTimeInterval(TimeInterval(seconds)))
    }

    /// 还剩几秒 (向上取整, 不小于 0)。向上取整: 显示「1 秒」时按钮还不能点, 到 0 才能点。
    public static func remaining(until deadline: Date, now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Self.remaining(until: deadline, now: context.date)
            if left > 0 {
                Text("\(left) 秒后可\(title)")
                    .font(theme.type.footnote.monospacedDigit())
                    .foregroundStyle(theme.color.textTertiary)
                    .contentTransition(.numericText(countsDown: true))
                    .frame(minHeight: 44)
            } else {
                Button(title) {
                    deadline = Date.now.addingTimeInterval(TimeInterval(seconds))
                    onResend()
                }
                .font(theme.type.footnote)
                .foregroundStyle(theme.color.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("zx.codeEntry.resend")
            }
        }
    }
}

#if DEBUG
private struct ZXCodeEntryPreview: View {
    @State private var code = ""
    @State private var phase: ZXCodeEntryPhase = .editing
    @Environment(\.zxTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.md) {
            Text("输入 123456 通过, 其他失败").font(theme.type.footnote).foregroundStyle(theme.color.textSecondary)
            ZXCodeEntry(code: $code, phase: phase) { value in
                phase = .verifying
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.6))
                    phase = value == "123456" ? .succeeded : .failed
                }
            }
            HStack {
                ZXResendCountdown(seconds: 5) { code = ""; phase = .editing }
                Spacer()
                Button("重置") { code = ""; phase = .editing }
                    .font(theme.type.footnote)
            }
        }
    }
}

#Preview("验证码") {
    PreviewPage {
        ZXCodeEntryPreview()
    }
}
#endif
