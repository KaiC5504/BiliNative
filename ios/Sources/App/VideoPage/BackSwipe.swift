import ObjectiveC
import UIKit

/// The stack's swipe back from the left edge. Every other drag (the player's seek, the 简介/评论 pager, the lists)
/// waits until a touch is known not to be that swipe; in build 5 the pager and the player took it. Full screen has
/// no swipe back. UIKit's own delegate still decides everything else.
final class BackSwipe: NSObject, UIGestureRecognizerDelegate {
    private nonisolated(unsafe) weak var original: UIGestureRecognizerDelegate?
    private nonisolated(unsafe) static var key: UInt8 = 0

    private init(original: UIGestureRecognizerDelegate?) {
        self.original = original
    }

    @MainActor
    static func install(on navigation: UINavigationController) {
        guard let pop = navigation.interactivePopGestureRecognizer, !(pop.delegate is BackSwipe) else { return }
        let swipe = BackSwipe(original: pop.delegate)
        // The recogniser holds its delegate weakly.
        objc_setAssociatedObject(pop, &key, swipe, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        pop.delegate = swipe
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard OrientationController.shared.presentation == .inline else { return false }
        return original?.gestureRecognizerShouldBegin?(recognizer) ?? true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
