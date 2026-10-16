import Foundation

/// Decides when to report playback progress; the caller does the network call.
public struct HeartbeatSchedule {
    /// Sent as the progress value once the video has been watched to the end.
    public static let finished = -1

    public let interval: Double
    private var baseline = 0.0

    public init(interval: Double = 15) {
        self.interval = interval
    }

    public mutating func tick(position: Double, playing: Bool) -> Int? {
        guard playing, position - baseline >= interval else { return nil }
        baseline = position
        return Int(position)
    }

    /// For events that always report (pause, seek done, part change, leaving).
    public mutating func mark(position: Double) -> Int {
        baseline = position
        return Int(position)
    }
}
