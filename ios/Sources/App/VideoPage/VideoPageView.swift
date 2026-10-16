import SwiftUI
import UIKit
import BiliAPI
import AppLogic

struct VideoPageView: View {
    let route: VideoRoute
    /// Tests drive the open panel from outside; the page owns it otherwise.
    private let panelOverride: Binding<PlayerPanel?>?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: VideoPageModel?
    @State private var chrome = ChromeState()
    @State private var ownPanel: PlayerPanel?
    @State private var danmakuSlot = DanmakuSlot()
    @State private var sender: DanmakuSendModel?
    @State private var sendBarOpen = false
    @State private var showLogin = false
    #if DEBUG
    @State private var sendDemo: DanmakuSendBar.Demo?
    #endif

    init(route: VideoRoute, panel: Binding<PlayerPanel?>? = nil) {
        self.route = route
        panelOverride = panel
    }

    private var panel: Binding<PlayerPanel?> { panelOverride ?? $ownPanel }

    var body: some View {
        ZStack {
            if let model {
                PageLayout(model: model, chrome: chrome, panel: panel, danmaku: danmakuView(for: model),
                           danmakuEnabled: env.settings.danmaku.enabled,
                           onToggleDanmaku: { env.settings.danmaku.enabled.toggle() }, onSendDanmaku: openSendBar)
                PanelLayer(panel: panel, model: model, onNeedLogin: presentLogin)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            if sendBarOpen, let sender {
                sendBar(sender)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLogin) { LoginView() }
        .onAppear {
            let page = model ?? env.makeVideoPageModel(route: route)
            model = page
            if sender == nil { sender = makeSender(for: page) }
            OrientationController.shared.begin()
            page.appear()
            #if DEBUG
            ChromeDemo.stage(page: page, chrome: chrome)
            DanmakuSendDemo.stage(page: page, chrome: chrome) { demo in
                sendDemo = demo
                sendBarOpen = true
            }
            #endif
        }
        .onDisappear {
            sendBarOpen = false
            model?.disappear()
            OrientationController.shared.end()
        }
        .onChange(of: sender?.needsLogin) { _, needsLogin in
            if needsLogin == true { presentLogin() }
        }
        .onChange(of: sendBarOpen) { _, open in
            chrome.panelOpen = open || panel.wrappedValue != nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model?.backgrounded() }
        }
        .onChange(of: model?.detail?.isVertical) { _, vertical in
            OrientationController.shared.videoIsVertical = vertical ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: DeviceControls.hardwareVolumeChanged)) { note in
            if let volume = note.userInfo?["volume"] as? Double { chrome.showHardwareVolume(volume) }
        }
        .onChange(of: OrientationController.shared.presentation) { _, presentation in
            if presentation == .inline { sendBarOpen = false }
        }
        .onChange(of: panel.wrappedValue == nil) { _, closed in
            chrome.panelOpen = !closed || sendBarOpen
        }
        .task { await openDemoPanel() }
    }

    private func openDemoPanel() async {
        #if DEBUG
        guard let demo = DemoPanel.requested else { return }
        if DemoPanel.landscape {
            try? await Task.sleep(for: .seconds(1))
            OrientationController.shared.enterLandscape()
        }
        try? await Task.sleep(for: .seconds(2.5))
        panel.wrappedValue = demo
        #endif
    }

    private func danmakuView(for model: VideoPageModel) -> UIView? {
        danmakuSlot.view(for: model, settings: env.settings)
    }

    private func makeSender(for page: VideoPageModel) -> DanmakuSendModel {
        let env = self.env
        return DanmakuSendModel(client: env.client, page: page, danmaku: page.danmaku,
                                isVip: {
                                    if case .loggedIn(_, let vip) = env.account { return vip }
                                    return false
                                },
                                isLoggedIn: {
                                    switch env.account {
                                    // Still checking the account: the server's answer decides.
                                    case .loggedIn, .unknown: return true
                                    case .loggedOut, .expired: return false
                                    }
                                })
    }

    @ViewBuilder
    private func sendBar(_ sender: DanmakuSendModel) -> some View {
        #if DEBUG
        DanmakuSendBar(model: sender, onClose: { sendBarOpen = false }, demo: sendDemo)
        #else
        DanmakuSendBar(model: sender, onClose: { sendBarOpen = false })
        #endif
    }

    private func openSendBar() {
        guard let sender else { return }
        guard sender.loggedIn else {
            sender.needsLogin = true
            return
        }
        sendBarOpen = true
    }

    /// Full screen is the same page rotated, so it goes back to inline before the sheet comes up.
    private func presentLogin() {
        sender?.needsLogin = false
        sendBarOpen = false
        let orientation = OrientationController.shared
        let rotates = orientation.presentation != .inline
        if rotates { orientation.exitToInline() }
        Task {
            if rotates { try? await Task.sleep(for: .milliseconds(450)) }
            showLogin = true
        }
    }
}

private struct PageLayout: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let danmaku: UIView?
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void

    var body: some View {
        let presentation = OrientationController.shared.presentation
        let inline = presentation == .inline
        GeometryReader { geometry in
            let box = CGSize(width: geometry.size.width, height: inline ? geometry.size.width * 9 / 16 : geometry.size.height)
            VStack(spacing: 0) {
                // Full screen ignores the safe area, so the chrome keeps clear of it itself.
                PlayerBox(model: model, chrome: chrome, panel: $panel, danmaku: danmaku, size: box, presentation: presentation,
                          insets: ScreenInsets.current(merging: geometry.safeAreaInsets), danmakuEnabled: danmakuEnabled,
                          onToggleDanmaku: onToggleDanmaku, onSendDanmaku: onSendDanmaku)
                    .frame(width: box.width, height: box.height)
                    .background(Color.black.ignoresSafeArea(edges: .top))
                if inline {
                    InfoSection(model: model)
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: inline ? [] : .all)
        .background((inline ? Color(uiColor: .systemBackground) : Color.black).ignoresSafeArea())
        // 09 keeps the status bar, light on black; landscape hides it (04).
        .statusBarHidden(presentation == .landscape)
        .preferredColorScheme(presentation == .vertical ? .dark : nil)
        .persistentSystemOverlays(inline ? .automatic : .hidden)
    }
}

private struct PlayerBox: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let danmaku: UIView?
    let size: CGSize
    let presentation: OrientationController.Presentation
    let insets: EdgeInsets
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    @Environment(AppEnvironment.self) private var env

    private var inline: Bool { presentation == .inline }

    /// 竖屏 full screen sets a landscape video above the middle (09); a vertical one fills the height.
    private var surfaceHeight: CGFloat {
        guard presentation == .vertical, model.detail?.isVertical != true else { return size.height }
        return size.height * VerticalLayout.videoCentre * 2
    }

    var body: some View {
        ZStack {
            Color.black
            // Stays mounted across parts, so the host view and its picture in picture survive a switch.
            PlayerSurface(player: model.controller?.player, fit: env.settings.fit, mirrored: model.mirrored,
                          allowsLevelGestures: !inline,
                          onGesture: { chrome.handle($0, page: model, size: size) },
                          // The end screens (26, 27) show no danmaku over the last frame.
                          danmaku: model.ended ? nil : danmaku,
                          onHost: { [weak model] in model?.host = $0 })
                .frame(height: surfaceHeight)
                .frame(maxHeight: .infinity, alignment: .top)
            if let controller = model.controller {
                if env.settings.showOverlay {
                    StatsOverlay(stats: controller.overlay, mode: controller.mode, quality: qualityLine(controller))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 36)
                        .transition(.opacity)
                }
            }
            ChromeLayer(model: model, chrome: chrome, panel: $panel, insets: insets, danmakuEnabled: danmakuEnabled,
                        onToggleDanmaku: onToggleDanmaku, onSendDanmaku: onSendDanmaku)
            status
        }
        .clipped()
        .animation(.smooth(duration: 0.25), value: env.settings.showOverlay)
    }

    @ViewBuilder
    private var status: some View {
        if let message = model.loadError {
            failure(message)
        } else if case .failed(let message)? = model.controller?.phase {
            failure(message)
        } else if model.controller == nil || model.controller?.phase == .loading {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .allowsHitTesting(false)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.retry() }
            } label: {
                Text("重试")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: Theme.Metrics.pillHeight)
                    .background(Theme.pink, in: Capsule())
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    private func qualityLine(_ controller: PlaybackControlling) -> String? {
        controller.playing.map { playing in
            playing.line(qualityName: controller.qualities.first { $0.id == playing.quality }?.name)
        }
    }
}

/// Build A shows only the title and the 分P strip under the player; build B brings the full 简介.
private struct InfoSection: View {
    let model: VideoPageModel

    var body: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .padding(.horizontal, Theme.Metrics.gutter)
                if detail.pages.count > 1 {
                    PartStrip(model: model, detail: detail)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PartStrip: View {
    let model: VideoPageModel
    let detail: VideoDetail

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(detail.pages, id: \.cid) { page in
                    let selected = model.current?.cid == page.cid
                    Button {
                        guard !selected else { return }
                        Task { await model.play(PlayItem(bvid: detail.bvid, cid: page.cid), at: nil) }
                    } label: {
                        Text("P\(page.page) \(page.part)")
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Theme.pink : Theme.text)
                            .padding(.horizontal, 14)
                            .frame(height: Theme.Metrics.pillHeight)
                            .background(selected ? Theme.pinkTint : Theme.pageGrey,
                                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
        }
    }
}
