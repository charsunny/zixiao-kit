//  LifeRailGesture.swift — 年轨的手势仲裁: 点一下跳年份, 按住再拖跳卷, 普通的滑动照常滚页
//
//  为什么不用 SwiftUI 手势: 年轨是盖在滚动视图上的一层, 只要它能被点中, 从它上面起手的滑动就
//  永远到不了 UIScrollView (D2 的「从屏幕前沿起手一滑就跳卷」)。SwiftUI 没有「这一下归我、
//  那一下放行」的仲裁, `simultaneousGesture` 又会让滚动与拖轨同时动。
//
//  做法: 年轨的画面不接触摸 (`allowsHitTesting(false)`); 这里在长卷所在的 UIScrollView 上挂两只
//  UIKit 识别器, 都只收落在年轨那一条 (屏幕前沿 22pt) 里的触摸:
//  - 轻点 (`UITapGestureRecognizer`): 抬手时报 y → 跳到最近的年份标签。
//  - 按住 0.25 秒 (`UILongPressGestureRecognizer`, 允许 8pt 抖动) → 进入拖轨, 之后的移动一路报 y。
//    按住一旦成立, UIKit 的默认互斥让滚动视图的 pan 失败, 拖轨时页面不会自己滚。
//  - 起手就滑 (8pt 内没停够 0.25 秒): 按住失败, pan 照常开始 —— 普通滚动穿过年轨。
//  识别器装在 UIScrollView 上而不是自己的视图上, 所以不挡任何触摸; 找 UIScrollView 靠一个
//  放在滚动内容里、本身不接触摸的空 UIView 往上找父视图。

import SwiftUI
import UIKit

enum LifeRailScrubPhase {
    case began, changed, ended
}

struct LifeRailGestureHook: UIViewRepresentable {
    /// 年轨在窗口坐标里的框 (SwiftUI `.global`)。
    var railFrame: CGRect
    /// 轻点, y 为年轨内坐标。
    var onTap: (CGFloat) -> Void
    /// 按住后拖动, y 为年轨内坐标。
    var onScrub: (LifeRailScrubPhase, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HookView {
        let view = HookView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: HookView, context: Context) {
        let coordinator = context.coordinator
        coordinator.railFrame = railFrame
        coordinator.onTap = onTap
        coordinator.onScrub = onScrub
        coordinator.isRightToLeft = context.environment.layoutDirection == .rightToLeft
        view.coordinator = coordinator
        view.attachIfNeeded()
    }

    static func dismantleUIView(_ view: HookView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 空视图: 进窗口时往上找 UIScrollView, 把识别器装上去。
    final class HookView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            guard window != nil, let coordinator else { return }
            var node = superview
            while let current = node, !(current is UIScrollView) { node = current.superview }
            if let scrollView = node as? UIScrollView { coordinator.attach(to: scrollView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var railFrame: CGRect = .zero
        var onTap: (CGFloat) -> Void = { _ in }
        var onScrub: (LifeRailScrubPhase, CGFloat) -> Void = { _, _ in }
        var isRightToLeft = false
        /// 按住多久进入拖轨。
        static let armDuration: TimeInterval = 0.25
        /// 按住期间允许的抖动; 超过就当作滚动, 放行。
        static let armSlop: CGFloat = 8
        /// 年轨上下各多收一点 (首末标签贴着两端)。
        static let verticalSlop: CGFloat = 12

        private weak var scrollView: UIScrollView?
        private lazy var press: UILongPressGestureRecognizer = {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
            recognizer.minimumPressDuration = Self.armDuration
            recognizer.allowableMovement = Self.armSlop
            recognizer.delegate = self
            recognizer.name = "life.rail.press"
            return recognizer
        }()
        private lazy var tap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.delegate = self
            recognizer.name = "life.rail.tap"
            return recognizer
        }()

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            scrollView.addGestureRecognizer(press)
            scrollView.addGestureRecognizer(tap)
            self.scrollView = scrollView
            #if DEBUG
            nudgeObserver = NotificationCenter.default.addObserver(forName: Self.debugNudge, object: nil, queue: .main) {
                [weak self] note in
                guard let delta = note.object as? CGFloat else { return }
                MainActor.assumeIsolated {
                    guard let scrollView = self?.scrollView else { return }
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x,
                                                        y: scrollView.contentOffset.y + delta), animated: false)
                }
            }
            #endif
        }

        #if DEBUG
        /// 截图用 (`-lifeNudge <pt>`): 把长卷的内容偏移再推若干点, 拍视差的中间态。
        static let debugNudge = Notification.Name("life.debug.nudge")
        private var nudgeObserver: NSObjectProtocol?
        #endif

        func detach() {
            #if DEBUG
            if let nudgeObserver { NotificationCenter.default.removeObserver(nudgeObserver) }
            nudgeObserver = nil
            #endif
            scrollView?.panGestureRecognizer.isEnabled = true
            scrollView?.removeGestureRecognizer(press)
            scrollView?.removeGestureRecognizer(tap)
            scrollView = nil
        }

        /// 收触摸的区域: 年轨那一条, 横向贴到屏幕前沿。
        private var hitRect: CGRect {
            guard railFrame.width > 0, railFrame.height > 0 else { return .null }
            let window = scrollView?.window?.bounds ?? .zero
            let minX = isRightToLeft ? railFrame.minX : min(railFrame.minX, window.minX)
            let maxX = isRightToLeft ? max(railFrame.maxX, window.maxX) : railFrame.maxX
            return CGRect(x: minX, y: railFrame.minY - Self.verticalSlop,
                          width: maxX - minX, height: railFrame.height + Self.verticalSlop * 2)
        }

        private func railY(_ recognizer: UIGestureRecognizer) -> CGFloat {
            let y = recognizer.location(in: nil).y - railFrame.minY
            return min(max(y, 0), railFrame.height)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            hitRect.contains(touch.location(in: nil))
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onTap(railY(recognizer))
        }

        @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                // 拖轨期间关掉滚动视图的 pan (SwiftUI 只管 isScrollEnabled, 不碰这个开关),
                // 手指怎么动页面都只跟年轨走; 松手再开。
                scrollView?.panGestureRecognizer.isEnabled = false
                onScrub(.began, railY(recognizer))
            case .changed:
                onScrub(.changed, railY(recognizer))
            case .ended, .cancelled, .failed:
                scrollView?.panGestureRecognizer.isEnabled = true
                onScrub(.ended, railY(recognizer))
            default:
                break
            }
        }
    }
}
