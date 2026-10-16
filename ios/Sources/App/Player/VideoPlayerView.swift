import AVKit
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onFullScreenChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.delegate = context.coordinator
        context.coordinator.onFullScreenChange = onFullScreenChange
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onFullScreenChange = onFullScreenChange
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onFullScreenChange: (Bool) -> Void = { _ in }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            onFullScreenChange(true)
            coordinator.animate(alongsideTransition: nil) { context in
                if context.isCancelled { self.onFullScreenChange(false) }
            }
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            coordinator.animate(alongsideTransition: nil) { context in
                if !context.isCancelled { self.onFullScreenChange(false) }
            }
        }
    }
}
