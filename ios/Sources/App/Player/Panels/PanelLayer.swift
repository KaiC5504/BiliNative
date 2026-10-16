import SwiftUI

enum PlayerPanel: Identifiable, CaseIterable {
    case quality, codec, speed, more, episodes, danmakuSettings

    var id: Self { self }

    /// "panel.quality" and so on; the UIKit probe inside each panel carries the same string.
    var identifier: String { "panel.\(self)" }
}

/// The pickers and panels over the player. It covers the whole screen (the portrait sheet needs more than the
/// player box) and passes every touch through while nothing is open.
struct PanelLayer: View {
    @Binding var panel: PlayerPanel?
    let model: VideoPageModel
    @Environment(AppEnvironment.self) private var env
    @State private var toastMessage: String?
    @State private var loginPresented = false

    init(panel: Binding<PlayerPanel?>, model: VideoPageModel) {
        _panel = panel
        self.model = model
    }

    var body: some View {
        ZStack {
            if let panel {
                content(panel)
            }
        }
        .animation(.smooth(duration: 0.25), value: panel)
        .toast($toastMessage)
        .sheet(isPresented: $loginPresented) { LoginView() }
    }

    @ViewBuilder
    private func content(_ panel: PlayerPanel) -> some View {
        switch panel {
        case .quality, .codec:
            SidePanel(identifier: panel.identifier, style: .side(width: 0.3), dismiss: close) {
                if panel == .codec {
                    CodecPanel(model: model, back: { self.panel = .quality }, close: close)
                } else {
                    QualityPanel(model: model, isVip: isVip, openCodec: { self.panel = .codec }, toast: show, close: close)
                }
            }
        case .speed:
            SidePanel(identifier: panel.identifier, style: .column, portraitHeight: 0.32, dismiss: close) {
                SpeedPanel(model: model, close: close)
            }
        case .more:
            SidePanel(identifier: panel.identifier, dismiss: close) {
                MorePanel(model: model, toast: show, requestLogin: { loginPresented = true }, close: close)
            }
        case .episodes:
            SidePanel(identifier: panel.identifier, dismiss: close) {
                EpisodesPanel(model: model, close: close)
            }
        case .danmakuSettings:
            SidePanel(identifier: panel.identifier, dismiss: close) {
                DanmakuSettingsPanel(onNeedLogin: { loginPresented = true })
            }
        }
    }

    private var isVip: Bool {
        if case .loggedIn(_, let vip) = env.account { return vip }
        return false
    }

    private func close() {
        panel = nil
    }

    private func show(_ message: String) {
        toastMessage = message
    }
}
