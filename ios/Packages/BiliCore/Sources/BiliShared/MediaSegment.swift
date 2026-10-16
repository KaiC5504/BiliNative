public struct MediaSegment: Hashable, Sendable {
    public let index: Int
    public let range: ByteRange
    /// Seconds from the start of the presentation.
    public let startTime: Double
    public let duration: Double

    public init(index: Int, range: ByteRange, startTime: Double, duration: Double) {
        self.index = index
        self.range = range
        self.startTime = startTime
        self.duration = duration
    }

    public var endTime: Double { startTime + duration }
}
