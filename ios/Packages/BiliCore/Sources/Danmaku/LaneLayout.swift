import Foundation

/// Collision-free lanes for scrolling, top and bottom danmaku. Times are seconds on the player's clock.
public struct LaneLayout: Sendable {
    public enum Kind: Sendable {
        case scroll
        case top
        case bottom
    }

    private struct Scrolling {
        var start: Double
        var width: Double
    }

    private var lanes: Int
    private var screenWidth: Double
    private var scrollDuration: Double
    private let staticDuration: Double
    private var scrolling: [Scrolling?]
    private var topBusyUntil: [Double]
    private var bottomBusyUntil: [Double]

    public init(lanes: Int, width: Double, scrollDuration: Double, staticDuration: Double = 4) {
        let count = max(lanes, 0)
        self.lanes = count
        self.screenWidth = width
        self.scrollDuration = scrollDuration
        self.staticDuration = staticDuration
        self.scrolling = Array(repeating: nil, count: count)
        self.topBusyUntil = Array(repeating: -Double.infinity, count: count)
        self.bottomBusyUntil = Array(repeating: -Double.infinity, count: count)
    }

    /// The lane, 0 being the top line, or nil when none is free and the danmaku is dropped.
    public mutating func place(_ kind: Kind, width w: Double, at t: Double) -> Int? {
        switch kind {
        case .scroll:
            let speed = (screenWidth + w) / scrollDuration
            for lane in 0..<lanes where fitsScroll(lane, speed: speed, at: t) {
                scrolling[lane] = Scrolling(start: t, width: w)
                return lane
            }
            return nil
        case .top:
            for lane in 0..<lanes where topBusyUntil[lane] <= t {
                topBusyUntil[lane] = t + staticDuration
                return lane
            }
            return nil
        case .bottom:
            for index in 0..<lanes where bottomBusyUntil[index] <= t {
                bottomBusyUntil[index] = t + staticDuration
                return lanes - 1 - index
            }
            return nil
        }
    }

    public mutating func reset(lanes: Int, width: Double, scrollDuration: Double) {
        let count = max(lanes, 0)
        self.lanes = count
        self.screenWidth = width
        self.scrollDuration = scrollDuration
        scrolling = Array(repeating: nil, count: count)
        topBusyUntil = Array(repeating: -Double.infinity, count: count)
        bottomBusyUntil = Array(repeating: -Double.infinity, count: count)
    }

    private func fitsScroll(_ lane: Int, speed: Double, at t: Double) -> Bool {
        guard let ahead = scrolling[lane] else { return true }
        let aheadSpeed = (screenWidth + ahead.width) / scrollDuration
        let fullyEntered = (t - ahead.start) * aheadSpeed >= ahead.width
        let cannotCatchUp = (ahead.start + scrollDuration - t) * speed <= screenWidth
        return fullyEntered && cannotCatchUp
    }
}
