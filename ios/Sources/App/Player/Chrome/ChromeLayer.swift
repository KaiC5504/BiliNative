import SwiftUI
import UIKit
import AppLogic
import BiliAPI

/// The controls over the player: the small player's (15), landscape (04) or 竖屏 (09) by
/// `OrientationController.presentation`, the gesture HUD, and the end screens.
struct ChromeLayer: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    /// The screen's safe area; full screen ignores it, so the controls keep clear of it themselves.
    var insets = EdgeInsets()
    var danmakuEnabled = true
    var onToggleDanmaku: () -> Void = {}
    var onSendDanmaku: () -> Void = {}
    /// The page's actions, for the full-screen icons, 关注 and the end screens.
    @Environment(ActionsModel.self) private var actions: ActionsModel?
    var onComments: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let presentation = OrientationController.shared.presentation
        ZStack {
            if model.ended {
                endScreen(presentation)
                    .transition(.opacity)
            } else {
                switch presentation {
                case .inline:
                    PortraitControls(model: model, chrome: chrome, panel: $panel, onBack: back)
                case .landscape:
                    LandscapeChrome(model: model, chrome: chrome, panel: $panel, insets: insets, actions: actions,
                                    danmakuEnabled: danmakuEnabled, onToggleDanmaku: onToggleDanmaku,
                                    onSendDanmaku: onSendDanmaku, onBack: back, onComments: onComments)
                case .vertical:
                    VerticalChrome(model: model, chrome: chrome, panel: $panel, insets: insets, actions: actions,
                                   danmakuEnabled: danmakuEnabled, onToggleDanmaku: onToggleDanmaku,
                                   onSendDanmaku: onSendDanmaku, onBack: back, onComments: onComments)
                }
                PlayerHUD(hud: chrome.hud)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.ended)
        .onAppear { chrome.touch() }
    }

    @ViewBuilder
    private func endScreen(_ presentation: OrientationController.Presentation) -> some View {
        switch presentation {
        case .inline:
            EndScreenPortrait(model: model, actions: actions, panel: $panel, onBack: back, onOpen: open)
        case .landscape:
            EndScreenLandscape(model: model, insets: insets, actions: actions, onBack: back, onOpen: open)
        case .vertical:
            // The 竖屏 page keeps the small player's end screen, over the band where the video sits.
            GeometryReader { geometry in
                EndScreenPortrait(model: model, actions: actions, panel: $panel, onBack: back, onOpen: open)
                    .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * VerticalLayout.videoCentre)
            }
        }
    }

    /// A related video opens on a page of its own (spec 4.1). Nothing pushes from full screen, so it goes inline first.
    private func open(_ card: VideoCard) {
        let orientation = OrientationController.shared
        guard orientation.presentation != .inline else { return model.openRelated(card) }
        orientation.exitToInline()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            model.openRelated(card)
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

/// The screen's safe area. A reader that ignores the safe area is told it has none (the first compile check's
/// full-screen shots drew under the status bar and the notch), so the window is asked as well.
@MainActor
enum ScreenInsets {
    static func current(merging proxy: EdgeInsets) -> EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.keyWindow ?? scene?.windows.first
        let insets = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: max(proxy.top, insets.top), leading: max(proxy.leading, insets.left),
                          bottom: max(proxy.bottom, insets.bottom), trailing: max(proxy.trailing, insets.right))
    }
}

enum VerticalLayout {
    /// In 09 a landscape video sits above the middle, centred at 41.5% of the screen's height.
    static let videoCentre: CGFloat = 0.415
}
