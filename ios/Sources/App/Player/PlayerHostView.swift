import AVFoundation
import AVKit
import UIKit
import DevLog

enum FitMode: String, CaseIterable {
    case fit, fill, stretch, ratio16x9, ratio4x3

    var label: String {
        switch self {
        case .fit: "适应"
        case .fill: "填充"
        case .stretch: "拉伸"
        case .ratio16x9: "16:9"
        case .ratio4x3: "4:3"
        }
    }
}

/// The video, the danmaku layer and the gesture view in one plain UIView, so rotation and picture in picture
/// never move it into a system controller (build 1 crashed that way with AVPlayerViewController).
final class PlayerHostView: UIView, AVPictureInPictureControllerDelegate {
    /// The AVPlayerLayer lives on its own subview rather than as this view's layer: the 16:9 and 4:3 modes
    /// letterbox its frame and mirroring flips it, neither of which may touch danmaku or gestures.
    final class VideoView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    let videoView = VideoView()
    let danmakuContainer = UIView()
    let gestureView = PlayerGestureView()
    private(set) var pip: AVPictureInPictureController?
    private(set) var pipError: Error?
    private var itemObservation: NSKeyValueObservation?

    var playerLayer: AVPlayerLayer { videoView.playerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            guard newValue !== playerLayer.player else { return }
            playerLayer.player = newValue
            itemObservation = newValue?.observe(\.currentItem, options: [.initial, .new]) { player, _ in
                let item = player.currentItem
                Task { @MainActor in PlayerHostView.attachVideoOutput(to: item) }
            }
            if newValue != nil { makePiPIfNeeded() }
        }
    }

    var fit: FitMode = .fit {
        didSet {
            guard fit != oldValue else { return }
            playerLayer.videoGravity = Self.gravity(for: fit)
            setNeedsLayout()
        }
    }

    var mirrored = false {
        didSet {
            guard mirrored != oldValue else { return }
            videoView.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        videoView.backgroundColor = .black
        playerLayer.videoGravity = Self.gravity(for: fit)
        danmakuContainer.isUserInteractionEnabled = false
        danmakuContainer.backgroundColor = .clear
        addSubview(videoView)
        addSubview(danmakuContainer)
        addSubview(gestureView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frame = Self.videoFrame(for: fit, in: bounds)
        // bounds and center, not frame: frame is undefined while the mirror transform is set.
        videoView.bounds = CGRect(origin: .zero, size: frame.size)
        videoView.center = CGPoint(x: frame.midX, y: frame.midY)
        danmakuContainer.frame = bounds
        gestureView.frame = bounds
    }

    func setDanmaku(_ view: UIView?) {
        let current = danmakuContainer.subviews
        if let view, current.count == 1, current[0] === view { return }
        if view == nil, current.isEmpty { return }
        current.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.frame = danmakuContainer.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        danmakuContainer.addSubview(view)
    }

    func startPiP() {
        guard let pip else {
            Logger.shared.warn(.player, "picture in picture unavailable", ["supported": .init(AVPictureInPictureController.isPictureInPictureSupported())])
            return
        }
        guard pip.isPictureInPicturePossible else {
            Logger.shared.warn(.player, "picture in picture not possible yet")
            return
        }
        pipError = nil
        pip.startPictureInPicture()
    }

    static func gravity(for fit: FitMode) -> AVLayerVideoGravity {
        switch fit {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        case .stretch, .ratio16x9, .ratio4x3: .resize
        }
    }

    static func videoFrame(for fit: FitMode, in bounds: CGRect) -> CGRect {
        switch fit {
        case .fit, .fill, .stretch: bounds
        case .ratio16x9: AVMakeRect(aspectRatio: CGSize(width: 16, height: 9), insideRect: bounds)
        case .ratio4x3: AVMakeRect(aspectRatio: CGSize(width: 4, height: 3), insideRect: bounds)
        }
    }

    /// FrameCapture reads frames from this output; it is cheap until a frame is copied.
    static func attachVideoOutput(to item: AVPlayerItem?) {
        guard let item, !item.outputs.contains(where: { $0 is AVPlayerItemVideoOutput }) else { return }
        item.add(AVPlayerItemVideoOutput(pixelBufferAttributes: nil))
    }

    private func makePiPIfNeeded() {
        guard pip == nil, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.delegate = self
        pip = controller
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Logger.shared.info(.player, "picture in picture started")
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Logger.shared.info(.player, "picture in picture stopped")
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Logger.shared.warn(.player, "picture in picture failed to start", ["error": .init(String(describing: error))])
        Task { @MainActor in self.pipError = error }
    }
}
