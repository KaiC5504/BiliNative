import ObjectiveC
import UIKit

/// The stack's swipe back from the left edge. UIKit's own delegate refuses it on pages that hide the navigation bar
/// (build 6 on iOS 27: no swipe back from 简介 or 评论), so this decides instead: a page to go back to, no transition
/// running, not in full screen, and nothing over the page that claimed the swipe (评论详情 closes first). Every
/// other drag (the player's seek, the 简介/评论 pager, the lists) waits until a touch is known not to be that swipe.
/// UIKit's delegate still answers the questions not asked here.
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
    private nonisolated(unsafe) static var key: UInt8 = 0

    private init(navigation: UINavigationController, original: UIGestureRecognizerDelegate?) {
        self.navigation = navigation
        self.original = original
    }

    @MainActor
    static func install(on navigation: UINavigationController) {
        guard let pop = navigation.interactivePopGestureRecognizer, !(pop.delegate is BackSwipe) else { return }
        let swipe = BackSwipe(navigation: navigation, original: pop.delegate)
        // Recognisers hold their delegates weakly.
        objc_setAssociatedObject(pop, &key, swipe, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        pop.delegate = swipe
        pop.isEnabled = true
        let claimed = ClaimedSwipe()
        objc_setAssociatedObject(claimed.recognizer, &key, claimed, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        navigation.view.addGestureRecognizer(claimed.recognizer)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard Self.claim == nil, let navigation, navigation.viewControllers.count > 1,
              navigation.transitionCoordinator == nil else { return false }
        return OrientationController.shared.presentation == .inline
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        Self.waitsForEdge(other)
    }

    /// The other drags; the two edge swipes never both begin.
    static func waitsForEdge(_ other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && !(other is UIScreenEdgePanGestureRecognizer)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}

/// The left-edge swipe while something has claimed it.
private final class ClaimedSwipe: NSObject, UIGestureRecognizerDelegate {
    let recognizer = UIScreenEdgePanGestureRecognizer()

    override init() {
        super.init()
        recognizer.edges = .left
        recognizer.delegate = self
        recognizer.addTarget(self, action: #selector(dragged(_:)))
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        BackSwipe.claim != nil && OrientationController.shared.presentation == .inline
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        BackSwipe.waitsForEdge(other)
    }

    @objc private func dragged(_ recognizer: UIScreenEdgePanGestureRecognizer) {
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
