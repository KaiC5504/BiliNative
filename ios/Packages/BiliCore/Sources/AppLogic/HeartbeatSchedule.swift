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
        guard playing, position.isFinite, position - baseline >= interval else { return nil }
        baseline = position
        return seconds(position)
    }

    /// For events that always report (pause, seek done, part change, leaving).
    public mutating func mark(position: Double) -> Int {
        baseline = position.isFinite ? position : 0
        return seconds(position)
    }

    /// CMTime.seconds is NaN while seeking or leaving; a stray negative must not read as the `finished` marker.
    private func seconds(_ position: Double) -> Int {
        Int(position.isFinite ? max(position, 0) : 0)
    }
}
