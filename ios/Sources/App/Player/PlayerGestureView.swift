import UIKit
import AppLogic

enum PlayerGestureEvent: Equatable {
    case tap, doubleTap, holdBegan, holdEnded
    case seekChanged(dx: Double), seekEnded(dx: Double)
    case levelChanged(side: Side, dy: Double), levelEnded(side: Side)

    enum Side { case left, right }
}

final class PlayerGestureView: UIView, UIGestureRecognizerDelegate {
    var onEvent: (PlayerGestureEvent) -> Void = { _ in }
    /// Vertical drags for brightness and volume; off in the small player so the page scrolls instead.
    var allowsLevelGestures = false
    /// Leaves the screen edges to the system's own gestures in full screen.
    var ignoresEdges = false

    let pan: UIPanGestureRecognizer
    private let tap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let hold = UILongPressGestureRecognizer()
    private var axis: GestureMath.Axis?
    private var side: PlayerGestureEvent.Side = .left

    /// `pan` is injectable so tests can hand in a recogniser with a synthetic translation.
    init(pan: UIPanGestureRecognizer = UIPanGestureRecognizer()) {
        self.pan = pan
        super.init(frame: .zero)
        backgroundColor = .clear
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        hold.minimumPressDuration = 0.35
        pan.maximumNumberOfTouches = 1
        tap.addTarget(self, action: #selector(tapped(_:)))
        doubleTap.addTarget(self, action: #selector(doubleTapped(_:)))
        hold.addTarget(self, action: #selector(held(_:)))
        pan.addTarget(self, action: #selector(panned(_:)))
        let recognizers: [UIGestureRecognizer] = [tap, doubleTap, hold, pan]
        for recognizer in recognizers {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        // UIKit also asks this view about recognisers it doesn't own, such as the page's scroll view.
        guard recognizer === pan else { return super.gestureRecognizerShouldBegin(recognizer) }
        let locked = Self.lockAxis(pan.translation(in: self))
        guard locked == .horizontal || allowsLevelGestures else { return false }
        axis = locked
        return true
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard ignoresEdges, let window else { return true }
        return !Self.isNearEdge(touch.location(in: window), of: window.bounds)
    }

    static func isNearEdge(_ point: CGPoint, of bounds: CGRect) -> Bool {
        !bounds.insetBy(dx: CGFloat(GestureMath.edgeInset), dy: CGFloat(GestureMath.edgeInset)).contains(point)
    }

    /// The recogniser begins after its own slop, which is about the lock distance; below it the larger component decides.
    static func lockAxis(_ translation: CGPoint) -> GestureMath.Axis {
        let dx = Double(translation.x), dy = Double(translation.y)
        return GestureMath.axis(dx: dx, dy: dy) ?? (abs(dy) > abs(dx) ? GestureMath.Axis.vertical : GestureMath.Axis.horizontal)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { onEvent(.tap) }
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { onEvent(.doubleTap) }
    }

    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: onEvent(.holdBegan)
        case .ended, .cancelled, .failed: onEvent(.holdEnded)
        default: break
        }
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        if recognizer.state == .began {
            side = recognizer.location(in: self).x < bounds.midX ? .left : .right
        }
        let axis = self.axis ?? Self.lockAxis(translation)
        switch recognizer.state {
        case .began, .changed:
            onEvent(axis == .horizontal ? .seekChanged(dx: Double(translation.x)) : .levelChanged(side: side, dy: Double(translation.y)))
        case .ended, .cancelled, .failed:
            onEvent(axis == .horizontal ? .seekEnded(dx: Double(translation.x)) : .levelEnded(side: side))
            self.axis = nil
        default:
            break
        }
    }
}
