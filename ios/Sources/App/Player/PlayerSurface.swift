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
    /// Hands out the host view once, for callers that drive it directly (小窗播放 calls `startPiP`).
    var onHost: ((PlayerHostView) -> Void)? = nil

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        apply(to: view)
        onHost?(view)
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        apply(to: view)
    }

    @MainActor private func apply(to view: PlayerHostView) {
        view.player = player
        view.fit = fit
        view.mirrored = mirrored
        view.gestureView.allowsLevelGestures = allowsLevelGestures
        // Level gestures are only on in full screen, which is also where the edges belong to the system.
        view.gestureView.ignoresEdges = allowsLevelGestures
        view.gestureView.onEvent = onGesture
        view.setDanmaku(danmaku)
    }
}
