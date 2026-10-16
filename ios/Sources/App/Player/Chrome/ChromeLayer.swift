import SwiftUI
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
    /// The action icons and 关注 need build B's actions (Task 21).
    var showsActions = false
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
                    LandscapeChrome(model: model, chrome: chrome, panel: $panel, insets: insets, showsActions: showsActions,
                                    danmakuEnabled: danmakuEnabled, onToggleDanmaku: onToggleDanmaku,
                                    onSendDanmaku: onSendDanmaku, onBack: back)
                case .vertical:
                    VerticalChrome(model: model, chrome: chrome, panel: $panel, insets: insets, showsActions: showsActions,
                                   danmakuEnabled: danmakuEnabled, onToggleDanmaku: onToggleDanmaku,
                                   onSendDanmaku: onSendDanmaku, onBack: back)
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
            EndScreenPortrait(model: model, panel: $panel, onBack: back, onOpen: open)
        case .landscape:
            EndScreenLandscape(model: model, insets: insets, showsActions: showsActions, onBack: back, onOpen: open)
        case .vertical:
            // The 竖屏 page keeps the small player's end screen, over the band where the video sits.
            GeometryReader { geometry in
                EndScreenPortrait(model: model, panel: $panel, onBack: back, onOpen: open)
                    .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * VerticalLayout.videoCentre)
            }
        }
    }

    /// Build A switches in place; build B's related list pushes a page instead (spec 4.1).
    private func open(_ card: VideoCard) {
        Task { await model.switchTo(PlayItem(bvid: card.bvid, cid: card.cid)) }
    }

    private func back() {
        if OrientationController.shared.presentation != .inline {
            OrientationController.shared.exitToInline()
        } else {
            dismiss()
        }
    }
}

enum VerticalLayout {
    /// In 09 a landscape video sits above the middle, centred at 41.5% of the screen's height.
    static let videoCentre: CGFloat = 0.415
}
