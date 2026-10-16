import Ripper

struct OverlayStats: Equatable {
    var firstFrameMs: Double?
    var lastSeekMs: Double?
    var stalls = 0
    var downloadBps: Double = 0
    var ripper: RipperStats?
}
