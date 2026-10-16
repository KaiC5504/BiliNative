import SwiftUI
import UIKit
import BiliAPI
import AppLogic

struct VideoPageView: View {
    let route: VideoRoute
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: VideoPageModel?
    @State private var chrome = ChromeState()
    @State private var panel: PlayerPanel?
    /// Stands in until Task 12's danmaku settings own the switch.
    @State private var danmakuEnabled = true

    var body: some View {
        ZStack {
            if let model {
                PageLayout(model: model, chrome: chrome, panel: $panel, danmaku: danmakuView(for: model),
                           danmakuEnabled: danmakuEnabled, onToggleDanmaku: { danmakuEnabled.toggle() }, onSendDanmaku: {})
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let page = model ?? env.makeVideoPageModel(route: route)
            model = page
            OrientationController.shared.begin()
            page.appear()
            #if DEBUG
            ChromeDemo.stage(page: page, chrome: chrome)
            #endif
        }
        .onDisappear {
            model?.disappear()
            OrientationController.shared.end()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model?.backgrounded() }
        }
        .onChange(of: model?.detail?.isVertical) { _, vertical in
            OrientationController.shared.videoIsVertical = vertical ?? false
        }
        .onChange(of: panel == nil) { _, closed in
            chrome.panelOpen = !closed
        }
    }

    /// The danmaku renderer goes into the player here (Task 12); nil draws none.
    private func danmakuView(for model: VideoPageModel) -> UIView? {
        nil
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
                // Full screen ignores the safe area, so the reader's insets are the screen's and the chrome keeps clear of them.
                PlayerBox(model: model, chrome: chrome, panel: $panel, danmaku: danmaku, size: box, presentation: presentation,
                          insets: geometry.safeAreaInsets, danmakuEnabled: danmakuEnabled,
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
                          danmaku: danmaku)
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
            PanelLayer(panel: $panel, model: model)
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
