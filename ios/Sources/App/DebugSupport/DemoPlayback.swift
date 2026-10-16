#if DEBUG
import AVFoundation
import CoreGraphics
import Observation
import BiliAPI

/// Stands in for PlaybackController on demo screens: plays the compile check's test media (MEDIA_DIR)
/// straight through AVPlayer. Without the media the player box stays black.
@MainActor
@Observable
final class DemoPlayback: PlaybackControlling {
    let player = AVPlayer()
    private(set) var phase: PlaybackController.Phase = .idle
    let mode: PlaybackController.Mode = .ripper
    let overlay = OverlayStats()
    let playing: PlayingStream? = nil
    let qualities = [QualityOption(id: 120, name: "超清 4K"), QualityOption(id: 80, name: "高清 1080P"),
                     QualityOption(id: 64, name: "高清 720P"), QualityOption(id: 32, name: "清晰 480P")]
    private(set) var selectedQuality = 80
    var playingQuality: Int? { selectedQuality }
    private(set) var codec: VideoCodec = .hevc
    private(set) var btrEnabled = true
    let resume: (timeMs: Int64, cid: Int64)? = nil
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var buffered: Double = 0
    private(set) var isPlaying = false
    let videoSize: CGSize? = CGSize(width: 1920, height: 1080)
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if player.rate > 0 { player.rate = rate }
        }
    }
    @ObservationIgnored var onEnd: (@MainActor () -> Void)?
    @ObservationIgnored var onPosition: (@MainActor (Double) -> Void)?

    @ObservationIgnored private let media: URL?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var pauseAt: Double? = UserDefaults.standard.object(forKey: "DemoPauseAt") != nil
        ? UserDefaults.standard.double(forKey: "DemoPauseAt") : nil

    init(media: URL? = DemoPlayback.testMedia) {
        self.media = media
    }

    nonisolated static var testMedia: URL? {
        guard let directory = ProcessInfo.processInfo.environment["MEDIA_DIR"] else { return nil }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("avc-video.mp4")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func start(at time: Double, autoplay: Bool) async {
        detach()
        position = time
        guard let media else {
            phase = .playing
            return
        }
        phase = .loading
        let item = AVPlayerItem(url: media)
        player.replaceCurrentItem(with: item)
        attach(item)
        if time > 0 {
            _ = await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        phase = .playing
        if autoplay { play() }
    }

    func stop() {
        detach()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        phase = .idle
    }

    func play() {
        player.defaultRate = rate
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) async {
        position = seconds
        _ = await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setQuality(_ quality: Int) async { selectedQuality = quality }
    func setCodec(_ codec: VideoCodec) async { self.codec = codec }
    func setBTR(_ enabled: Bool) async { btrEnabled = enabled }

    private func attach(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time, item: item) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
                self?.onEnd?()
            }
        }
    }

    private func detach() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func tick(_ time: CMTime, item: AVPlayerItem) {
        let seconds = time.seconds.isFinite ? time.seconds : 0
        // `-DemoPauseAt <seconds>` freezes a screenshot mid-playback.
        if let pauseAt, isPlaying, seconds >= pauseAt {
            self.pauseAt = nil
            pause()
        }
        position = seconds
        let total = item.duration.seconds
        if total.isFinite, total > 0 { duration = total }
        buffered = item.loadedTimeRanges.map(\.timeRangeValue).map(\.end.seconds).max() ?? seconds
        isPlaying = player.timeControlStatus != .paused
        onPosition?(seconds)
    }
}
#endif
