public struct RipperConfig: Sendable {
    public var firstByteTimeoutMs = 5_500.0
    public var stallTimeoutMs = 4_000.0
    public var attemptTimeoutMs = 15_000.0
    public var hedgeDelayMs = 900.0
    public var minChunkBytes: Int64 = 64 * 1024
    public var pieceRounds = 3
    public var retryWindowMs = 25_000.0
    /// nil = AutoConcurrency decides.
    public var fixedConcurrency: Int?
    public var prefetchVideoBytes: Int64 = 64 << 20
    public var prefetchAudioBytes: Int64 = 8 << 20
    public var prefetchAheadSeconds = 45.0
    /// Base priority of player requests; prefetch runs at 10.
    public var priority = 50.0
    /// Off restores the engine without hurry mode: the bench's baseline and a kill switch.
    public var hurry = true
    /// A segment starting less than this much playback ahead of the playhead is fetched in a hurry.
    public var hurryAheadSeconds = 10.0

    public init() {}
}
