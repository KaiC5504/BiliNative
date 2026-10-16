import Foundation

/// Times a user's seek from the jump until playback moves again.
struct SeekTimer {
    private var started: (at: Date, position: Double)?
    private var reloading = false

    var isRunning: Bool { started != nil }

    /// A reload seeks to where playback was; that jump is not the user's, up to the reload's first playing.
    mutating func reloadBegan() {
        reloading = true
        started = nil
    }

    /// A seek while paused is not timed: the wait would include however long the user stays paused.
    /// Returns true when timing started.
    mutating func jumped(to position: Double, at now: Date, rate: Float) -> Bool {
        guard !reloading, rate > 0 else {
            started = nil
            return false
        }
        started = (now, position)
        return true
    }

    /// The player started playing; returns the seek's milliseconds if one was being timed.
    mutating func playing(at now: Date) -> Double? {
        reloading = false
        guard let started else { return nil }
        self.started = nil
        return max(0, now.timeIntervalSince(started.at) * 1000)
    }

    /// A seek inside the buffer may never leave playing. Once the playhead has moved on from the jump, playback
    /// resumed `advanced / rate` seconds ago; returns the seek's milliseconds then.
    mutating func ticked(position: Double, rate: Float, playing: Bool, at now: Date) -> Double? {
        guard let started, playing, rate > 0 else { return nil }
        let advanced = position - started.position
        guard advanced >= 0.2 else { return nil }
        self.started = nil
        return max(0, (now.timeIntervalSince(started.at) - advanced / Double(rate)) * 1000)
    }

    /// The user paused before playback resumed; the wait from here on is theirs, not the player's.
    mutating func paused() {
        started = nil
    }

    mutating func cancel() {
        started = nil
        reloading = false
    }
}

/// AVPlayer reports a stall for the wait after a drag too, sometimes just before the jump itself is reported.
/// A stall counts only when no jump came within a second before it or 0.75 s after.
struct StallFilter {
    static let before: TimeInterval = 1.0
    static let after: TimeInterval = 0.75
    /// The wait after a jump is not a stall, but one this long is lag the viewer feels; direct mode waited 9-12 s.
    static let slowSeekMs = 1_000.0
    private var lastJump: Date?

    static func isLag(seekMs: Double) -> Bool { seekMs > slowSeekMs }

    mutating func jumped(at now: Date) {
        lastJump = now
    }

    /// Ask `after` seconds past the stall, once a jump that belongs to it has had time to arrive.
    func isSeekWait(stalledAt: Date) -> Bool {
        guard let lastJump else { return false }
        let gap = lastJump.timeIntervalSince(stalledAt)
        return gap >= -Self.before && gap <= Self.after
    }
}
