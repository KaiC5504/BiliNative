import SwiftUI
import BiliAPI
import DevLog

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var manualText = ""
    @State private var opening = false
    @State private var errorText: String?
    @State private var partChoice: VideoView?
    @State private var route: VideoRoute?
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var confirmClear = false
    @State private var stubPanel = false // TEMP

    var body: some View {
        NavigationStack {
            List {
                Section("账号") { AccountRow(showLogin: $showLogin) }
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        Task { await open(strings.first ?? "") }
                    }
                    .buttonBorderShape(.capsule)
                    .disabled(opening)
                    HStack {
                        TextField("粘贴链接、BV 号或分享文字", text: $manualText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { Task { await open(manualText) } }
                        Button("打开") { Task { await open(manualText) } }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .disabled(opening || manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } header: {
                    Text("打开视频")
                } footer: {
                    Text("支持 b23.tv 短链、BV 号、av 号和 App 里的分享文字")
                }
                if !env.recents.items.isEmpty {
                    Section {
                        ForEach(env.recents.items) { item in
                            Button { route = item.videoRoute } label: { RecentRow(item: item) }
                        }
                    } header: {
                        HStack {
                            Text("最近打开")
                            Spacer()
                            Button("清空") { confirmClear = true }
                                .font(.footnote)
                                .confirmationDialog("清空最近打开的视频？", isPresented: $confirmClear, titleVisibility: .visible) {
                                    Button("清空", role: .destructive) { env.recents.clear() }
                                }
                        }
                    }
                }
            }
            .animation(.snappy, value: env.recents.items)
            .animation(.snappy, value: errorText)
            .navigationTitle(AppInfo.displayName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(item: $route) { VideoPageView(route: $0).id($0.id) }
            .sheet(isPresented: $showLogin) { LoginView() }
            // TEMP: shows the 弹幕设置 panel until the real page wiring lands.
            .fullScreenCover(isPresented: $stubPanel) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    DanmakuSettingsPanel().padding(.horizontal, 20)
                }
                .environment(env)
            }
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
                        .padding(28)
                        .glassEffect(in: .rect(cornerRadius: 22))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: opening)
            .task {
                #if DEBUG
                switch UserDefaults.standard.string(forKey: "DemoScreen") {
                case "settings": showSettings = true
                case "page": route = VideoRoute(bvid: VideoPageFixtures.bvidA)
                case "danmaku-panel-stub", "panel-danmaku-more", "block-words": stubPanel = true
                default: break
                }
                #endif
                if env.account == .unknown { await env.refreshAccount() }
            }
        }
        .tint(.pink)
    }

    private func open(_ text: String) async {
        guard !opening else { return }
        errorText = nil
        guard let link = LinkParser.parse(text) else {
            errorText = BiliError.invalidLink.userMessage
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
                errorText = "该视频没有可播放的分P"
            }
            manualText = ""
        } catch is CancellationError {
            return
        } catch {
            Logger.shared.warn(.ui, "open failed", ["error": .init(String(describing: error))])
            errorText = Self.userMessage(error)
        }
    }

    private func go(_ view: VideoView, _ page: VideoPage) {
        partChoice = nil
        let next = PlayerRoute(bvid: view.bvid, cid: page.cid, title: view.title, part: page.part, page: page.page, pageCount: view.pages.count)
        env.recents.add(next)
        route = next.videoRoute
    }

    private static func userMessage(_ error: Error) -> String {
        if let error = error as? BiliError { return error.userMessage }
        if error is URLError { return "网络连接失败，请检查网络后重试" }
        return "打开视频失败，请稍后重试"
    }
}

private struct RecentRow: View {
    let item: PlayerRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.pink.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2).foregroundStyle(.primary)
                if item.pageCount > 1 {
                    Text("P\(item.page) \(item.part)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
