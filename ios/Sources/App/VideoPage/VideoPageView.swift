import SwiftUI
import UIKit
import BiliAPI
import AppLogic
import DevLog

struct VideoPageView: View {
    let route: VideoRoute
    /// Tests drive the open panel from outside; the page owns it otherwise.
    private let panelOverride: Binding<PlayerPanel?>?
    /// The same for the coin dialog, the favourites sheet and the unfollow confirm.
    private let promptsOverride: ActionPrompts?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: VideoPageModel?
    @State private var lifecycle = PageLifecycle()
    @State private var chrome = ChromeState()
    @State private var ownPanel: PlayerPanel?
    @State private var danmakuSlot = DanmakuSlot()
    @State private var sender: DanmakuSendModel?
    @State private var sendBarOpen = false
    @State private var tabs = PageTabsState()
    /// Made once the video's aid is known, and again for each video the page switches to.
    @State private var comments: CommentsModel?
    @State private var loginRequested = false
    @State private var actions: ActionsModel?
    @State private var actionToast: String?
    @State private var ownPrompts = ActionPrompts()
    #if DEBUG
    @State private var sendDemo: DanmakuSendBar.Demo?
    #endif

    init(route: VideoRoute, panel: Binding<PlayerPanel?>? = nil, prompts: ActionPrompts? = nil) {
        self.route = route
        panelOverride = panel
        promptsOverride = prompts
    }

    /// A page for a model that already exists: the one picture in picture kept after its page closed.
    init(model: VideoPageModel) {
        route = model.route
        panelOverride = nil
        promptsOverride = nil
        _model = State(initialValue: model)
    }

    private var panel: Binding<PlayerPanel?> { panelOverride ?? $ownPanel }
    private var prompts: ActionPrompts { promptsOverride ?? ownPrompts }

    var body: some View {
        ZStack {
            if let model {
                PageLayout(model: model, chrome: chrome, panel: panel, tabs: tabs, comments: comments, danmaku: danmakuView(for: model),
                           danmakuEnabled: env.settings.danmaku.enabled, ignoresKeyboard: sendBarOpen,
                           onToggleDanmaku: { env.settings.danmaku.enabled.toggle() }, onSendDanmaku: openSendBar,
                           onNeedLogin: presentLogin, onCompose: compose, onComments: showComments)
                    .environment(actions)
                PanelLayer(panel: panel, model: model, onNeedLogin: presentLogin)
                    .ignoresSafeArea()
                actionOverlay
                    .ignoresSafeArea()
                    .zIndex(1)
                if let viewing = comments?.viewing {
                    PictureViewer(viewing: viewing) { comments?.viewing = nil }
                        .transition(.opacity)
                        .zIndex(1)
                }
            } else {
                Color.black.ignoresSafeArea()
            }
            if sendBarOpen, let sender {
                sendBar(sender)
            }
        }
        .animation(.easeOut(duration: 0.2), value: comments?.viewing)
        .toast(Binding(get: { comments?.toast }, set: { comments?.toast = $0 }))
        .background { PageProbe(lifecycle: lifecycle) }
        .toolbar(.hidden, for: .navigationBar)
        .toast($actionToast)
        .loginGate($loginRequested)
        .alert("确定不再关注？", isPresented: Binding(get: { prompts.unfollowAsked }, set: { prompts.unfollowAsked = $0 })) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                guard let actions else { return }
                Task { await actions.toggleFollow() }
            }
        }
        .onAppear {
            let page = model ?? env.makeVideoPageModel(route: route)
            model = page
            if sender == nil { sender = makeSender(for: page) }
            lifecycle.appeared(page)
            #if DEBUG
            ChromeDemo.stage(page: page, chrome: chrome)
            ActionsDemo.stage(page: page, chrome: chrome)
            ActionPromptsDemo.stage(page: page, chrome: chrome) { actions }
            DanmakuSendDemo.stage(page: page, chrome: chrome) { demo in
                sendDemo = demo
                sendBarOpen = true
            }
            // Reads the state each time: the comments model only exists once the video has loaded.
            CommentsDemo.stage(page: page, tabs: tabs) { comments }
            #endif
        }
        .onDisappear {
            sendBarOpen = false
            lifecycle.disappeared()
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
        .onChange(of: model?.detail?.aid, initial: true) { _, aid in
            guard let aid, let detail = model?.detail, comments?.aid != aid else { return }
            comments = makeComments(aid: aid, upMid: detail.owner.mid)
        }
        .onChange(of: model?.detail?.isVertical) { _, vertical in
            guard let model else { return }
            OrientationController.shared.setVideoIsVertical(vertical ?? false, owner: model)
        }
        .onChange(of: model?.detail?.bvid, initial: true) { makeActions() }
        .onChange(of: model?.relation) { _, relation in
            if let relation { actions?.apply(relation) }
        }
        .onChange(of: model?.uploader) { _, uploader in
            if let uploader { actions?.apply(uploader) }
        }
        .onChange(of: env.account) { old, account in
            guard case .loggedIn = account, old != account, let actions else { return }
            Task { await actions.refreshRelation() }
        }
        .onChange(of: actions?.prompt) { _, prompt in
            if let prompt, let actions { handle(prompt, for: actions) }
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

    private func makeComments(aid: Int64, upMid: Int64) -> CommentsModel {
        let env = self.env
        return CommentsModel(client: env.client, aid: aid, upMid: upMid, isLoggedIn: { Self.loggedIn(env.account) },
                             requestLogin: presentLogin, ownMid: { env.mid })
    }

    /// Still checking the account: the server's answer decides.
    private static func loggedIn(_ account: AppEnvironment.Account) -> Bool {
        switch account {
        case .loggedIn, .unknown: return true
        case .loggedOut, .expired: return false
        }
    }

    /// The bottom bar and 回复. Task 25's composer opens from here.
    private func compose(_ target: ReplyTarget, emotes: Bool) {
        guard Self.loggedIn(env.account) else { return presentLogin() }
        comments?.toast = "发评论即将上线"
    }

    /// The 评论 icon in full screen: back to the page, on the 评论 tab.
    private func showComments() {
        OrientationController.shared.exitToInline()
        tabs.sheet = nil
        tabs.selection = .comments
    }

    private func makeSender(for page: VideoPageModel) -> DanmakuSendModel {
        let env = self.env
        return DanmakuSendModel(client: env.client, page: page, danmaku: page.danmaku,
                                isVip: {
                                    if case .loggedIn(_, let vip) = env.account { return vip }
                                    return false
                                },
                                isLoggedIn: { Self.loggedIn(env.account) })
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

    private func presentLogin() {
        sender?.needsLogin = false
        sendBarOpen = false
        loginRequested = true
    }

    /// One per video: autoplay into another 合集 episode brings another detail and a fresh set of actions.
    private func makeActions() {
        guard let model, let detail = model.detail, actions?.detail.bvid != detail.bvid else { return }
        let env = self.env
        actions = ActionsModel(client: env.client, detail: detail, relation: model.relation, uploader: model.uploader,
                               isLoggedIn: {
                                   switch env.account {
                                   case .loggedIn, .unknown: return true
                                   case .loggedOut, .expired: return false
                                   }
                               },
                               requestLogin: { presentLogin() },
                               toast: { actionToast = $0 })
        prompts.close()
        prompts.actions = actions
    }

    @ViewBuilder
    private var actionOverlay: some View {
        if let actions, let overlay = prompts.overlay {
            switch overlay {
            case .coin:
                CoinDialog(actions: actions, balance: prompts.balance, onClose: { prompts.close() })
            case .favourites:
                if let favourites = prompts.favourites {
                    FavouriteSheet(actions: actions, model: favourites, onClose: { prompts.close() })
                }
            }
        }
    }

    /// Taps that open something first.
    private func handle(_ prompt: ActionsModel.Prompt, for actions: ActionsModel) {
        actions.prompt = nil
        switch prompt {
        case .share:
            guard let detail = model?.detail else { return }
            let part = detail.pages.count > 1 ? model?.currentPage?.page : nil
            SharePresenter.present(title: detail.title, url: ShareLinks.video(detail.bvid, part: part)) { completed in
                if completed { Task { await actions.shared() } }
            }
        case .coin:
            // At the limit there is nothing to choose: coin() only says "已投满N个硬币".
            guard actions.maxCoins > 0 else {
                Task { await actions.coin(1, alsoLike: false) }
                return
            }
            let prompts = self.prompts
            prompts.balance = nil
            prompts.overlay = .coin
            let client = env.client
            Task {
                do {
                    let balance = try await client.coinBalance()
                    if prompts.overlay == .coin { prompts.balance = balance }
                } catch {
                    Logger.shared.warn(.api, "coin balance failed", ["error": .init(String(describing: error))])
                }
            }
        case .favourites:
            let env = self.env
            let favourites = FavouritesModel(client: env.client, aid: actions.detail.aid, mid: {
                if env.mid == nil { await env.refreshAccount() }
                return env.mid
            })
            prompts.favourites = favourites
            prompts.overlay = .favourites
            Task { await favourites.load() }
        case .unfollow:
            prompts.unfollowAsked = true
        }
    }
}

private struct PageLayout: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let tabs: PageTabsState
    let comments: CommentsModel?
    let danmaku: UIView?
    let danmakuEnabled: Bool
    /// While the danmaku bar is open the keyboard must not squeeze the page under it.
    let ignoresKeyboard: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    let onNeedLogin: () -> Void
    let onCompose: (ReplyTarget, _ emotes: Bool) -> Void
    let onComments: () -> Void
    @Environment(ActionsModel.self) private var actions: ActionsModel?

    var body: some View {
        let presentation = OrientationController.shared.presentation
        let inline = presentation == .inline
        GeometryReader { geometry in
            let collapsing = CollapsingPlayer(fullHeight: inline ? geometry.size.width * 9 / 16 : geometry.size.height)
            ZStack(alignment: .top) {
                if inline {
                    // Laid out as if the player were already the bar; each tab leaves the rest of its height free.
                    PageTabs(state: tabs, reserve: collapsing.reserve) {
                        IntroTab(model: model, state: tabs, following: actions?.following, onFollow: { actions?.tapFollow() },
                                 onNeedLogin: onNeedLogin) {
                            if let actions { ActionRow(actions: actions) }
                        }
                    } comments: {
                        if let comments {
                            CommentsTab(model: comments, tabs: tabs, onCompose: onCompose)
                        } else {
                            CommentsSlot(state: tabs)
                        }
                    }
                    .padding(.top, CollapsingPlayer.barHeight + Theme.Page.tabRowHeight)
                    .ignoresSafeArea(.container, edges: .bottom)
                }
                PlayerArea(model: model, chrome: chrome, panel: $panel, tabs: tabs, comments: comments, danmaku: danmaku,
                           width: geometry.size.width, collapsing: collapsing, presentation: presentation,
                           insets: ScreenInsets.current(merging: geometry.safeAreaInsets), danmakuEnabled: danmakuEnabled,
                           onToggleDanmaku: onToggleDanmaku, onSendDanmaku: onSendDanmaku, onCompose: onCompose,
                           onComments: onComments)
            }
        }
        .ignoresSafeArea(inline ? .keyboard : .all, edges: inline && !ignoresKeyboard ? [] : .all)
        .background((inline ? Theme.Page.background : Color.black).ignoresSafeArea())
        // 09 keeps the status bar, light on black; landscape hides it (04).
        .statusBarHidden(presentation == .landscape)
        .preferredColorScheme(presentation == .vertical ? .dark : nil)
        .persistentSystemOverlays(inline ? .automatic : .hidden)
        // Timestamps seek and video ids open a page, from the description and from every comment.
        .environment(\.richTextActions, RichTextActions(
            seek: { seconds in Task { await model.activate(.timestamp(label: "", seconds: seconds)) } },
            openVideo: { id in Task { await model.activate(.video(id: id)) } }))
        #if DEBUG
        .task { IntroDemo.stage(page: model, tabs: tabs) }
        #endif
    }
}

/// The player and, inline, the tab row under it. It alone follows the tabs' scrolling, so the tab content is not
/// rebuilt on every frame of a scroll.
private struct PlayerArea: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let tabs: PageTabsState
    let comments: CommentsModel?
    let danmaku: UIView?
    let width: CGFloat
    let collapsing: CollapsingPlayer
    let presentation: OrientationController.Presentation
    let insets: EdgeInsets
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    let onCompose: (ReplyTarget, _ emotes: Bool) -> Void
    let onComments: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var inline: Bool { presentation == .inline }

    /// Loaded and not playing, or at the end: only then does scrolling shrink the player.
    private var paused: Bool {
        guard let controller = model.controller else { return false }
        return model.ended || (controller.phase == .playing && !controller.isPlaying)
    }

    var body: some View {
        let height = inline ? collapsing.height(forOffset: tabs.offset, paused: paused) : collapsing.fullHeight
        let progress = inline ? collapsing.progress(height: height) : 0
        let box = CGSize(width: width, height: height)
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Full screen ignores the safe area, so the chrome keeps clear of it itself.
                PlayerBox(model: model, chrome: chrome, panel: $panel, danmaku: danmaku, size: box, presentation: presentation,
                          insets: insets, shrunk: progress > 0, danmakuEnabled: danmakuEnabled,
                          onToggleDanmaku: onToggleDanmaku, onSendDanmaku: onSendDanmaku, onComments: onComments)
                    .frame(width: box.width, height: box.height)
                    .background(Color.black.ignoresSafeArea(edges: .top))
                    .overlay {
                        if progress > 0 {
                            CollapsedPlayerBar(progress: progress, onResume: resume, onBack: { dismiss() },
                                               onMore: { panel = .more })
                        }
                    }
                if inline {
                    PageTabRow(state: tabs, replyCount: model.detail?.stat.reply, danmakuEnabled: danmakuEnabled,
                               danmakuClosed: model.danmaku.closed, onToggleDanmaku: onToggleDanmaku,
                               onSendDanmaku: onSendDanmaku)
                }
            }
            // 评论详情 covers the tab row as well as the list (13).
            if inline, let comments, let thread = comments.thread {
                ThreadView(model: comments, thread: thread, onCompose: onCompose)
                    .padding(.top, height)
                    .transition(.move(edge: .bottom))
            }
            if inline, let sheet = tabs.sheet, let detail = model.detail {
                sheetView(sheet, detail: detail)
                    .padding(.top, height)
            }
        }
        .animation(.smooth(duration: 0.3), value: comments?.thread?.root.rpid)
        .animation(.smooth(duration: 0.3), value: paused)
        .animation(.smooth(duration: 0.3), value: tabs.selection)
    }

    @ViewBuilder
    private func sheetView(_ sheet: PageSheet, detail: VideoDetail) -> some View {
        switch sheet {
        case .collection:
            if let season = detail.season {
                CollectionSheet(season: season, current: model.current, onChoose: { episode in
                    Task { await model.switchTo(PlayItem(bvid: episode.bvid, cid: episode.cid)) }
                }, onClose: { tabs.sheet = nil })
            }
        case .parts:
            PartList(detail: detail, current: model.current, onChoose: { page in
                Task { await model.play(PlayItem(bvid: detail.bvid, cid: page.cid), at: nil) }
            }, onClose: { tabs.sheet = nil })
        }
    }

    /// 继续播放: back to the top, where the player has its full height again.
    private func resume() {
        withAnimation(.smooth(duration: 0.3)) { tabs.scrollToTop() }
        model.play()
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
    /// Shrunk by the page's scrolling: no controls and no danmaku under the 继续播放 shade. The controls are hidden,
    /// not removed, so they keep their state for when it grows back.
    let shrunk: Bool
    let danmakuEnabled: Bool
    let onToggleDanmaku: () -> Void
    let onSendDanmaku: () -> Void
    let onComments: () -> Void
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
            // The page's one player and host view, so picture in picture stays on one layer across parts.
            PlayerSurface(player: model.player, fit: env.settings.fit, mirrored: model.mirrored,
                          allowsLevelGestures: !inline,
                          // Weak: the model holds the host view, which holds this closure.
                          onGesture: { [weak model, chrome, size] event in
                              if let model { chrome.handle(event, page: model, size: size) }
                          },
                          // The end screens (26, 27) show no danmaku over the last frame.
                          danmaku: model.ended || shrunk ? nil : danmaku,
                          host: model.host,
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
                        onToggleDanmaku: onToggleDanmaku, onSendDanmaku: onSendDanmaku, onComments: onComments)
                .opacity(shrunk ? 0 : 1)
                .allowsHitTesting(!shrunk)
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
            playing.line(qualityName: QualityNames.full(qn: playing.quality, serverText: controller.qualities.first { $0.id == playing.quality }?.name))
        }
    }
}

/// The 评论 tab before the video, and so its aid, has loaded.
private struct CommentsSlot: View {
    let state: PageTabsState

    var body: some View {
        ScrollView {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
        }
        .collapsingPlayerScroll(state, tab: .comments)
    }
}
