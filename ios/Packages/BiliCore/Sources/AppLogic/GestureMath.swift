import Foundation

public enum GestureMath {
    public static let seekSecondsPerWidth = 90.0
    public static let axisLockDistance = 10.0
    public static let edgeInset = 25.0

    public enum Axis: Sendable { case horizontal, vertical }

    /// nil until the finger has travelled far enough to tell a seek from a brightness/volume drag.
    public static func axis(dx: Double, dy: Double) -> Axis? {
        guard hypot(dx, dy) >= axisLockDistance else { return nil }
        return abs(dx) >= abs(dy) ? .horizontal : .vertical
    }

    public static func seekTarget(start: Double, dx: Double, width: Double, duration: Double) -> Double {
        let upper = max(0, duration)
        guard width > 0 else { return min(max(start, 0), upper) }
        return min(max(start + dx / width * seekSecondsPerWidth, 0), upper)
    }

    /// Brightness or volume after a vertical drag; dragging up raises it, a full height drag spans 0 to 1.
    public static func level(start: Double, dy: Double, height: Double) -> Double {
        guard height > 0 else { return min(max(start, 0), 1) }
        return min(max(start - dy / height, 0), 1)
    }
}
