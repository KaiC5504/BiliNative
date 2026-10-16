import SwiftUI

/// Interim chrome for build A's first page: a tap toggles play and pause, and back leaves.
/// Task 10 replaces `ChromeState` and the body of `ChromeLayer` with the official controls.
@MainActor
@Observable
final class ChromeState {
    var visible = true

    func handle(_ event: PlayerGestureEvent, page: VideoPageModel, size: CGSize) {
        switch event {
        case .tap, .doubleTap:
            page.togglePlay()
        default:
            break
        }
    }
}

struct ChromeLayer: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("返回")
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .overlay {
            if let controller = model.controller, controller.phase == .playing, !controller.isPlaying, !model.ended {
                Image(systemName: "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .allowsHitTesting(false)
            }
        }
    }

    private func back() {
        if OrientationController.shared.presentation != .inline {
            OrientationController.shared.exitToInline()
        } else {
            dismiss()
        }
    }
}
