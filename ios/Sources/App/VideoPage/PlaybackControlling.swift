import AVFoundation
import CoreGraphics
import BiliAPI

/// What the video page and its chrome need from playback, so tests and the demo screen can stand in for it.
@MainActor
protocol PlaybackControlling: AnyObject {
    var player: AVPlayer { get }
    var phase: PlaybackController.Phase { get }
    var mode: PlaybackController.Mode { get }
    var overlay: OverlayStats { get }
    /// The stream handed to AVPlayer, for the stats overlay.
    var playing: PlayingStream? { get }
    var qualities: [QualityOption] { get }
    var selectedQuality: Int { get }
    var playingQuality: Int? { get }
    var codec: VideoCodec { get }
    var btrEnabled: Bool { get }
    var resume: (timeMs: Int64, cid: Int64)? { get }
    var position: Double { get }
    var duration: Double { get }
    var buffered: Double { get }
    var isPlaying: Bool { get }
    var videoSize: CGSize? { get }
    var rate: Float { get set }
    var onEnd: (@MainActor () -> Void)? { get set }
    /// Called on every playhead update (every 0.25 s while playing).
    var onPosition: (@MainActor (Double) -> Void)? { get set }

    func start(at time: Double, autoplay: Bool) async
    func stop()
    func play()
    func pause()
    func seek(to seconds: Double) async
    func setQuality(_ quality: Int) async
    func setCodec(_ codec: VideoCodec) async
    func setBTR(_ enabled: Bool) async
}

extension PlaybackController: PlaybackControlling {}
