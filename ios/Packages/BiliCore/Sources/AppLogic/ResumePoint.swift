import Foundation

public enum ResumePoint {
    /// Where to start from the server's saved progress. The history cursor is per video, so it only counts for the part it was saved on.
    public static func start(lastPlayTimeMs: Int64, lastPlayCid: Int64, cid: Int64, duration: Double) -> Double {
        guard lastPlayCid == cid, lastPlayTimeMs > 0 else { return 0 }
        let seconds = Double(lastPlayTimeMs) / 1000
        return duration - seconds > 5 ? seconds : 0
    }
}
