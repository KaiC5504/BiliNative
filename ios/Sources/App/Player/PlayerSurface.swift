import AVFoundation
import SwiftUI

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer?
    var fit: FitMode = .fit
    var mirrored = false
    var allowsLevelGestures = false
    var onGesture: (PlayerGestureEvent) -> Void = { _ in }
    /// The danmaku renderer's view, drawn above the video and under the controls.
    var danmaku: UIView? = nil
    /// A host view to show instead of a new one. Picture in picture is tied to its layer, so a page brought back
    /// from the small window shows the view it left with.
    var host: PlayerHostView? = nil
    /// Hands out the host view once, for callers that drive it directly (小窗播放 calls `startPiP`).
    var onHost: ((PlayerHostView) -> Void)? = nil

    func makeUIView(context: Context) -> SurfaceContainer {
        let container = SurfaceContainer()
        let view = host ?? PlayerHostView()
        container.show(view)
        apply(to: view)
        onHost?(view)
        return container
    }

    func updateUIView(_ container: SurfaceContainer, context: Context) {
        guard let view = container.host else { return }
        apply(to: view)
    }

    static func dismantleUIView(_ container: SurfaceContainer, coordinator: ()) {
        container.release()
    }

    @MainActor private func apply(to view: PlayerHostView) {
        view.player = player
        view.fit = fit
        view.mirrored = mirrored
        view.gestureView.allowsLevelGestures = allowsLevelGestures
        // Level gestures are only on in full screen, which is also where the edges belong to the system.
        view.gestureView.ignoresEdges = allowsLevelGestures
        view.gestureView.onEvent = onGesture
        if LeakProbe.omits("noset") {
        } else if LeakProbe.omits("asyncdanmaku") {
            let danmaku = danmaku
            DispatchQueue.main.async { [weak view] in view?.setDanmaku(danmaku) }
        } else {
            view.setDanmaku(danmaku)
        }
    }
}

/// SwiftUI's own view around the page's host view. The host outlives its page for picture in picture, so it is
/// never handed to SwiftUI itself: a page's view tree stayed reachable from a host the page model kept, and no
/// closed page was ever freed. The host leaves the container, and drops the page's closures and danmaku view,
/// when SwiftUI tears the container down.
final class SurfaceContainer: UIView {
    private(set) var host: PlayerHostView?

    func show(_ view: PlayerHostView) {
        host?.removeFromSuperview()
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
        host = view
    }

    /// A page brought back from the small window may already have moved the host into its own container.
    func release() {
        guard let host else { return }
        self.host = nil
        guard host.superview === self else { return }
        host.gestureView.onEvent = { _ in }
        host.setDanmaku(nil)
        host.removeFromSuperview()
    }
}
