import SwiftUI
import BiliAPI

struct PlayerScreen: View {
    let route: PlayerRoute
    @Environment(AppEnvironment.self) private var env
    @State private var controller: PlaybackController?
    @State private var fullScreen = false
    @State private var resumeAt: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let controller {
                    VideoPlayerView(player: controller.player) { fullScreen = $0 }
                        .transition(.opacity)
                }
                if controller == nil || controller?.phase == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if let controller, env.settings.showOverlay {
                    StatsOverlay(stats: controller.overlay, mode: controller.mode)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)))
                }
            }
            .animation(.smooth(duration: 0.25), value: env.settings.showOverlay)
            .animation(.smooth(duration: 0.25), value: controller?.phase)
            if let controller {
                PlayerStatusBar(route: route, controller: controller)
                PlayerControls(controller: controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
        }
        .animation(.smooth, value: controller == nil)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
    }

    /// Playback runs in its own task so a view-lifecycle cancellation can never leave it half started;
    /// `stop()` is the only way it ends.
    private func appear() {
        if let controller {
            if controller.phase == .idle {
                let time = resumeAt
                Task { await controller.start(at: time) }
            }
            return
        }
        let settings = env.settings
        let next = PlaybackController(environment: env.playbackEnvironment(bvid: route.bvid, cid: route.cid),
                                      quality: settings.preferredQuality, codec: settings.preferredCodec, btrEnabled: settings.btrEnabled)
        controller = next
        Task { await next.start() }
    }

    /// Leaving the screen must stop the controller, or its RipperSession stays registered in the app-wide
    /// router. AVPlayerViewController's own full-screen presentation can hide this view without leaving it.
    private func disappear() {
        guard let controller, !fullScreen else { return }
        resumeAt = controller.currentSeconds
        controller.stop()
    }
}

private struct PlayerStatusBar: View {
    let route: PlayerRoute
    let controller: PlaybackController

    var body: some View {
        HStack(spacing: 8) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.15), in: Capsule())
                .contentTransition(.symbolEffect(.replace))
            if route.pageCount > 1 {
                Text("P\(route.page) \(route.part)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(.snappy, value: controller.phase)
        .animation(.snappy, value: controller.mode)
    }

    private var text: String {
        switch controller.phase {
        case .idle: return "已停止"
        case .loading: return "加载中"
        case .playing: return controller.mode.label
        case .failed: return "播放失败"
        }
    }

    private var icon: String {
        switch controller.phase {
        case .idle: return "stop.fill"
        case .loading: return "hourglass"
        case .failed: return "exclamationmark.triangle.fill"
        case .playing:
            switch controller.mode {
            case .ripper: return "bolt.fill"
            case .direct: return "arrow.right"
            case .directFallback: return "arrow.uturn.down"
            }
        }
    }

    private var tint: Color {
        switch controller.phase {
        case .idle, .loading: return .secondary
        case .failed: return .red
        case .playing:
            switch controller.mode {
            case .ripper: return .pink
            case .direct: return .blue
            case .directFallback: return .orange
            }
        }
    }
}

struct PlayerControls: View {
    let controller: PlaybackController
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        List {
            if case .failed(let message) = controller.phase {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Button {
                        Task { await controller.start(at: controller.currentSeconds) }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                }
            }
            Section("播放") {
                if controller.qualities.isEmpty {
                    LabeledContent("清晰度") { ProgressView() }
                } else {
                    Picker("清晰度", selection: Binding(get: { controller.selectedQuality }, set: { quality in
                        settings.preferredQuality = quality
                        Task { await controller.setQuality(quality) }
                    })) {
                        ForEach(controller.qualities, id: \.id) { Text($0.name).tag($0.id) }
                    }
                }
                Picker("编码", selection: Binding(get: { controller.codec }, set: { codec in
                    settings.preferredCodec = codec
                    Task { await controller.setCodec(codec) }
                })) {
                    ForEach(VideoCodec.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle(isOn: Binding(get: { controller.btrEnabled }, set: { enabled in
                    settings.btrEnabled = enabled
                    Task { await controller.setBTR(enabled) }
                })) {
                    Label("BTR 加速", systemImage: "bolt.horizontal.fill")
                }
                Toggle(isOn: $settings.showOverlay) {
                    Label("显示统计", systemImage: "chart.bar.xaxis")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .animation(.snappy, value: controller.phase)
        .animation(.snappy, value: controller.qualities)
    }
}
