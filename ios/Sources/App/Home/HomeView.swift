import SwiftUI
import BiliAPI
import DevLog

/// 首页 (01): the avatar and the link field, the 推荐 tab, and the feed.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var feed: FeedModel?
    @State private var linkText = ""
    @State private var opening = false
    @State private var toast: String?
    @State private var partChoice: VideoView?
    @State private var menuOpen = false
    @State private var showLogin = false
    @State private var showSettings = false
    /// Whether the feed on screen was fetched logged in; nil until the first account check has answered.
    @State private var feedSignedIn: Bool?

    var body: some View {
        @Bindable var navigator = env.navigator
        NavigationStack(path: $navigator.path) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    TopRow(text: $linkText, opening: opening, face: env.face,
                           onAvatar: { withAnimation(.snappy(duration: 0.25)) { menuOpen.toggle() } },
                           onSubmit: { Task { await open(linkText) } },
                           onPaste: { text in Task { await open(text) } })
                    RecommendTab()
                    Theme.divider.frame(height: 0.5)
                }
                .background(Theme.card.ignoresSafeArea(edges: .top))
                if let feed {
                    FeedGrid(feed: feed, onOpen: { openVideo(VideoRoute(bvid: $0.bvid)) }, onWatchLater: watchLater)
                } else {
                    Theme.pageGrey
                }
            }
            .background(Theme.pageGrey)
            .overlay(alignment: .topLeading) { menu }
            .toolbar(.hidden, for: .navigationBar)
            .videoPageDestinations(history: { HistoryView() }, recents: { RecentsView() })
            .sheet(isPresented: $showLogin) { LoginView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("选择分P", isPresented: Binding(get: { partChoice != nil }, set: { if !$0 { partChoice = nil } }),
                                titleVisibility: .visible, presenting: partChoice) { view in
                ForEach(view.pages, id: \.cid) { page in
                    Button("P\(page.page) \(page.part)") { go(view, page) }
                }
            } message: { view in
                Text(view.title)
            }
            .overlay {
                if opening {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.panelText)
                        .padding(28)
                        .background(Theme.toastFill, in: RoundedRectangle(cornerRadius: 16))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: opening)
            .toast($toast)
            .onChange(of: env.account, initial: true) { _, account in
                // Logging in or out changes what 推荐 recommends; the first check at launch does not.
                let signedIn: Bool
                switch account {
                case .unknown: return
                case .loggedIn: signedIn = true
                case .loggedOut, .expired: signedIn = false
                }
                defer { feedSignedIn = signedIn }
                guard let previous = feedSignedIn, previous != signedIn, let feed else { return }
                Task { await feed.refresh() }
            }
            .task {
                // The task runs again whenever a pushed page is popped; the feed and the demo staging happen once.
                if feed == nil {
                    let model = FeedModel(client: env.client)
                    feed = model
                    Task { await model.refresh() }
                    #if DEBUG
                    stageDemo()
                    #endif
                }
                if env.account == .unknown { await env.refreshAccount() }
            }
        }
        .tint(Theme.pink)
    }

    #if DEBUG
    private func stageDemo() {
        switch UserDefaults.standard.string(forKey: "DemoScreen") {
        case "settings": showSettings = true
        case "history": env.navigator.open(.history)
        case "home-menu": menuOpen = true
        case "leak-check": LeakCheckDemo.stage(navigator: env.navigator)
        case "page": openVideo(VideoRoute(bvid: VideoPageFixtures.bvidA))
        case "danmaku-send", "danmaku-style":
            openVideo(VideoRoute(bvid: VideoPageFixtures.bvidA, cid: VideoPageFixtures.cidA1, startSeconds: 20))
        case "danmaku-portrait":
            openVideo(VideoRoute(bvid: VideoPageFixtures.bvidA, cid: VideoPageFixtures.cidA1, startSeconds: 20))
        case "danmaku-landscape":
            openVideo(VideoRoute(bvid: VideoPageFixtures.bvidA, cid: VideoPageFixtures.cidA1, startSeconds: 20))
            Task {
                try? await Task.sleep(for: .seconds(2))
                OrientationController.shared.enterLandscape()
            }
        case let name:
            if let demo = ChromeDemo.route(for: name) { openVideo(demo) }
        }
    }
    #endif

    private var menu: some View {
        ZStack(alignment: .topLeading) {
            if menuOpen {
                Theme.scrim
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)
            }
            if menuOpen {
                AvatarMenu { item in
                    closeMenu()
                    switch item {
                    case .login: showLogin = true
                    case .history: env.navigator.open(.history)
                    case .recents: env.navigator.open(.recents)
                    case .settings: showSettings = true
                    }
                }
                .padding(.leading, TopRow.margin)
                .padding(.top, TopRow.height + 2)
                .transition(.scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity))
            }
        }
    }

    private func closeMenu() {
        withAnimation(.snappy(duration: 0.2)) { menuOpen = false }
    }

    private func watchLater(_ card: FeedCard) {
        Task {
            do {
                try await env.client.addToWatchLater(aid: card.aid)
                toast = "已添加至稍后再看"
            } catch let error as BiliError where error.needsLogin {
                showLogin = true
            } catch {
                Logger.shared.warn(.ui, "watch later failed", ["error": .init(String(describing: error))])
                toast = FeedModel.message(for: error)
            }
        }
    }

    private func open(_ text: String) async {
        guard !opening else { return }
        guard let link = LinkParser.parse(text) else {
            toast = BiliError.invalidLink.userMessage
            return
        }
        opening = true
        defer { opening = false }
        do {
            let (view, page) = try await env.client.resolve(link)
            Logger.shared.info(.ui, "open", ["bvid": .init(view.bvid), "pages": .init(view.pages.count)])
            if let page, let match = view.pages.first(where: { $0.page == page }) {
                go(view, match)
            } else if view.pages.count > 1 {
                partChoice = view
            } else if let first = view.pages.first {
                go(view, first)
            } else {
                Logger.shared.warn(.ui, "video has no pages", ["bvid": .init(view.bvid)])
                toast = "该视频没有可播放的分P"
            }
            linkText = ""
        } catch is CancellationError {
            return
        } catch {
            Logger.shared.warn(.ui, "open failed", ["error": .init(String(describing: error))])
            toast = Self.userMessage(error)
        }
    }

    private func go(_ view: VideoView, _ page: VideoPage) {
        partChoice = nil
        let next = PlayerRoute(bvid: view.bvid, cid: page.cid, title: view.title, part: page.part, page: page.page, pageCount: view.pages.count)
        env.recents.add(next)
        openVideo(next.videoRoute)
    }

    /// Every video page home opens (feed cards, pasted links, demo screens) goes through here.
    private func openVideo(_ next: VideoRoute) {
        env.navigator.open(next)
    }

    private static func userMessage(_ error: Error) -> String {
        if let error = error as? BiliError { return error.userMessage }
        if error is URLError { return "网络连接失败，请检查网络后重试" }
        return "打开视频失败，请稍后重试"
    }
}

/// The avatar and the rounded link field (01's search field).
private struct TopRow: View {
    static let height: CGFloat = 44
    static let margin: CGFloat = 15
    private static let avatar: CGFloat = 38
    private static let fieldHeight: CGFloat = 34

    @Binding var text: String
    let opening: Bool
    let face: String?
    let onAvatar: () -> Void
    let onSubmit: () -> Void
    let onPaste: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAvatar) {
                AccountAvatar(face: face, size: Self.avatar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("账号")
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                TextField("", text: $text, prompt: Text("粘贴链接或BV号").foregroundStyle(Theme.secondaryText))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(onSubmit)
                    .disabled(opening)
                    .onChange(of: text) { old, new in
                        // A paste lands as one big change; typing adds a character at a time.
                        if new.count - old.count > 1, LinkParser.parse(new) != nil {
                            focused = false
                            onPaste(new)
                        }
                    }
                if text.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let first = strings.first else { return }
                        Task { @MainActor in onPaste(first) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(Theme.pink)
                    .disabled(opening)
                } else {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.divider)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: Self.fieldHeight)
            .overlay(Capsule().stroke(Theme.secondaryText, lineWidth: 0.67))
            .contentShape(Capsule())
            .onTapGesture { focused = true }
        }
        .padding(.horizontal, Self.margin)
        .frame(height: Self.height)
    }
}

/// 01's tab row, with only 推荐 and that one selected.
private struct RecommendTab: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("推荐")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.pink)
            Capsule()
                .fill(Theme.pink)
                .frame(width: 18, height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits([.isHeader, .isSelected])
    }
}

private struct FeedGrid: View {
    let feed: FeedModel
    let onOpen: (FeedCard) -> Void
    let onWatchLater: (FeedCard) -> Void

    private let columns = [GridItem(.flexible(), spacing: FeedMetrics.spacing), GridItem(.flexible(), spacing: FeedMetrics.spacing)]

    var body: some View {
        ScrollView {
            if feed.cards.isEmpty {
                placeholder
                    .frame(maxWidth: .infinity)
                    .padding(.top, 160)
            } else {
                LazyVGrid(columns: columns, spacing: FeedMetrics.spacing) {
                    ForEach(Array(feed.cards.enumerated()), id: \.element.id) { index, card in
                        FeedCardView(card: card, onOpen: { onOpen(card) }, onWatchLater: { onWatchLater(card) })
                            .onAppear {
                                // Starts the next page a few cards before the end, so scrolling rarely waits.
                                if index >= feed.cards.count - 4, feed.error == nil {
                                    Task { await feed.loadMore() }
                                }
                            }
                    }
                }
                .padding(FeedMetrics.spacing)
                footer
            }
        }
        .refreshable { await feed.refresh() }
    }

    @ViewBuilder
    private var placeholder: some View {
        if let error = feed.error, !feed.loading {
            RetryMessage(message: error) { Task { await feed.refresh() } }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if let error = feed.error {
                RetryMessage(message: error) { Task { await feed.loadMore() } }
            } else {
                // Also asks by itself, in case the last cards were already on screen when the page before added nothing.
                ProgressView()
                    .onAppear { Task { await feed.loadMore() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }
}

/// The M1 recents list, now behind 最近打开.
struct RecentsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmClear = false

    var body: some View {
        List {
            ForEach(env.recents.items) { item in
                Button { env.navigator.open(item.videoRoute) } label: { RecentRow(item: item) }
            }
        }
        .overlay {
            if env.recents.items.isEmpty {
                Text("还没有打开过视频")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .animation(.snappy, value: env.recents.items)
        .navigationTitle("最近打开")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !env.recents.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") { confirmClear = true }
                }
            }
        }
        .confirmationDialog("清空最近打开的视频？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { env.recents.clear() }
        }
    }
}

private struct RecentRow: View {
    let item: PlayerRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.card)
                .frame(width: 40, height: 40)
                .background(Theme.pink.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2).foregroundStyle(Theme.text)
                if item.pageCount > 1 {
                    Text("P\(item.page) \(item.part)").font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.divider)
        }
        .contentShape(Rectangle())
    }
}
