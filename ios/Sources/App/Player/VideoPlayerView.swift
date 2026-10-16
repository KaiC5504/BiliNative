import AVKit
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Drawn in AVKit's content overlay: under its controls, and in its full screen too.
    var overlay: AnyView? = nil
    var onFullScreenChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let (controller, host) = Self.makeController(player: player, overlay: overlay ?? AnyView(EmptyView()))
        controller.delegate = context.coordinator
        context.coordinator.onFullScreenChange = onFullScreenChange
        context.coordinator.overlayHost = host
        return controller
    }

    static func makeController(player: AVPlayer, overlay: AnyView) -> (AVPlayerViewController, UIHostingController<AnyView>?) {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.loadViewIfNeeded()
        guard let contentOverlay = controller.contentOverlayView else { return (controller, nil) }
        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        controller.addChild(host)
        contentOverlay.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: contentOverlay.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: contentOverlay.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: contentOverlay.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: contentOverlay.bottomAnchor),
        ])
        host.didMove(toParent: controller)
        return (controller, host)
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onFullScreenChange = onFullScreenChange
        context.coordinator.overlayHost?.rootView = overlay ?? AnyView(EmptyView())
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onFullScreenChange: (Bool) -> Void = { _ in }
        var overlayHost: UIHostingController<AnyView>?

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
