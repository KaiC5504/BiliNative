import ObjectiveC
import UIKit

/// The stack's swipes back: from the left edge, and (iOS 26) from anywhere in the content. UIKit's own delegate
/// refuses both on pages that hide the navigation bar, and it does so in a private `_gestureRecognizer:
/// shouldReceiveEvent:` asked before anything public (builds 5-7: no swipe back from 简介 or 评论 on the phone, while
/// tests that asked the public methods passed). So this answers every receive and begin question itself: a page to
/// go back to, no transition running, not in full screen, and nothing over the page that claimed the swipe
/// (评论详情 closes first). The drags inside the page (the player's seek, the 简介/评论 pager, the lists) wait until
/// a touch is known not to be a swipe back; the content swipe gives way to the ones that want it.
/// UIKit's delegate still answers the other questions.
final class BackSwipe: NSObject, UIGestureRecognizerDelegate {
    enum Drag {
        case moved(CGFloat)
        case ended(close: Bool)
    }

    /// Something over the page that the swipe closes instead of the page, following the finger.
    struct Claim {
        let owner: ObjectIdentifier
        let handle: @MainActor (Drag) -> Void
    }

    @MainActor static var claim: Claim?

    private nonisolated(unsafe) weak var navigation: UINavigationController?
    private nonisolated(unsafe) weak var original: UIGestureRecognizerDelegate?
    private let edge: Bool
    private let start = TouchStart()
    private nonisolated(unsafe) static var key: UInt8 = 0

    private init(navigation: UINavigationController, original: UIGestureRecognizerDelegate?, edge: Bool) {
        self.navigation = navigation
        self.original = original
        self.edge = edge
    }

    @MainActor
    static func install(on navigation: UINavigationController) {
        guard let pop = navigation.interactivePopGestureRecognizer, !(pop.delegate is BackSwipe) else { return }
        take(pop, on: navigation, edge: true)
        if let content = navigation.interactiveContentPopGestureRecognizer {
            take(content, on: navigation, edge: false)
        }
        let claimed = ClaimedSwipe()
        objc_setAssociatedObject(claimed.recognizer, &key, claimed, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        navigation.view.addGestureRecognizer(claimed.recognizer)
    }

    @MainActor
    private static func take(_ recognizer: UIGestureRecognizer, on navigation: UINavigationController, edge: Bool) {
        let swipe = BackSwipe(navigation: navigation, original: recognizer.delegate, edge: edge)
        // Recognisers hold their delegates weakly.
        objc_setAssociatedObject(recognizer, &key, swipe, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        recognizer.delegate = swipe
        recognizer.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard Self.claim == nil, let navigation, navigation.viewControllers.count > 1,
              navigation.transitionCoordinator == nil,
              OrientationController.shared.presentation == .inline else { return false }
        return edge || start.allowsSwipeBack(in: recognizer)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        start.record(touch)
        return true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        Self.waits(other, for: recognizer)
    }

    /// The drags inside the page wait; the swipes on the navigation view itself never both begin.
    static func waits(_ other: UIGestureRecognizer, for swipe: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view !== swipe.view
    }

    override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        let name = NSStringFromSelector(selector)
        if name.contains("houldReceive") || name.contains("houldBegin") { return false }
        return original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}

/// Where a touch landed, for swipes that may begin anywhere.
private final class TouchStart {
    private nonisolated(unsafe) var touch: UITouch?
    private nonisolated(unsafe) weak var view: UIView?
    private var landed = CGPoint.zero

    func record(_ touch: UITouch) {
        self.touch = touch
        view = touch.view
        landed = touch.location(in: nil)
    }

    /// A rightward, mostly sideways move that nothing under the finger wants: no other drag (the player's seek)
    /// and no sideways scroller that can still scroll back (评论 pages back to 简介 first). Read from the touch:
    /// on a quick flick UIKit asks before the pan's own translation and velocity are set.
    func allowsSwipeBack(in recognizer: UIGestureRecognizer) -> Bool {
        guard let touch, let host = recognizer.view else { return false }
        let now = touch.location(in: nil)
        let moved = CGPoint(x: now.x - landed.x, y: now.y - landed.y)
        guard moved.x > 0, moved.x > abs(moved.y) else { return false }
        var current = view
        while let candidate = current, candidate !== host {
            if let scroller = candidate as? UIScrollView,
               scroller.contentSize.width > scroller.bounds.width + 1,
               scroller.contentOffset.x > -scroller.adjustedContentInset.left + 1 {
                return false
            }
            let drags = candidate.gestureRecognizers?.contains { other in
                other.isEnabled && other is UIPanGestureRecognizer
                    && other !== (candidate as? UIScrollView)?.panGestureRecognizer
            } ?? false
            if drags { return false }
            current = candidate.superview
        }
        return true
    }
}

/// The swipe back, from the edge or the middle, while something has claimed it.
private final class ClaimedSwipe: NSObject, UIGestureRecognizerDelegate {
    let recognizer = UIPanGestureRecognizer()
    private let start = TouchStart()

    override init() {
        super.init()
        recognizer.delegate = self
        recognizer.addTarget(self, action: #selector(dragged(_:)))
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        BackSwipe.claim != nil && OrientationController.shared.presentation == .inline
            && start.allowsSwipeBack(in: recognizer)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        start.record(touch)
        return true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        BackSwipe.waits(other, for: recognizer)
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view, let claim = BackSwipe.claim else { return }
        let x = max(0, recognizer.translation(in: view).x)
        switch recognizer.state {
        case .began, .changed:
            claim.handle(.moved(x))
        case .ended:
            claim.handle(.ended(close: x > view.bounds.width / 3 || recognizer.velocity(in: view).x > 500))
        case .cancelled, .failed:
            claim.handle(.ended(close: false))
        default:
            break
        }
    }
}
