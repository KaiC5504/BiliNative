import SwiftUI
import AppLogic
import BiliAPI

/// ⋮ (20, 21): the official panel's rows that make sense here, plus a 测试 card for the BTR switch and the stats overlay.
struct MorePanel: View {
    let model: VideoPageModel
    let toast: (String) -> Void
    let requestLogin: () -> Void
    let close: () -> Void

    enum Page { case root, timer, fit }

    enum SleepChoice: Equatable { case off, minutes15, minutes30, minutes60, custom }

    static func sleepChoice(for minutes: Int?) -> SleepChoice {
        switch minutes {
        case nil: .off
        case 15?: .minutes15
        case 30?: .minutes30
        case 60?: .minutes60
        default: .custom
        }
    }

    @State private var page = Page.root
    @State private var customMinutes = 30

    private var settings: AppSettings { model.settings }

    var body: some View {
        switch page {
        case .root: root
        case .timer: timer
        case .fit: fit
        }
    }

    private var root: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 36) {
                PanelActionButton(icon: "clock", title: "稍后再看", action: watchLater)
                PanelActionButton(icon: "pip.enter", title: "小窗播放", action: startPiP)
            }
            .padding(.leading, 6)

            PanelTitle("定时关闭")
                .padding(.top, 36)
            PanelGroup {
                PanelSegments(items: sleepItems, selection: Self.sleepChoice(for: model.sleepMinutes), select: chooseSleep)
                    .frame(height: PanelMetrics.rowHeight)
            }
            .padding(.top, 15)

            PanelGroup {
                PanelToggleRow(icon: "forward.end", title: "自动连播",
                               isOn: Binding(get: { settings.autoplay }, set: { settings.autoplay = $0 }))
                PanelRowFrame(icon: "repeat", title: "循环播放") {
                    PanelSegments(items: loopItems, selection: settings.loop, select: { settings.loop = $0 })
                }
                PanelToggleRow(icon: "flip.horizontal", title: "镜像翻转",
                               isOn: Binding(get: { model.mirrored }, set: { model.mirrored = $0 }))
                Button {
                    page = .fit
                } label: {
                    PanelRowFrame(icon: "aspectratio", title: "画面尺寸", showsDivider: false) {
                        Spacer(minLength: 8)
                        Text(settings.fit.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.panelSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.panelSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            PanelTitle("测试")
                .padding(.top, 36)
            PanelGroup {
                PanelToggleRow(icon: "bolt", title: "BTR 加速",
                               isOn: Binding(get: { settings.btrEnabled }, set: setBTR))
                PanelToggleRow(icon: "chart.bar", title: "显示统计", showsDivider: false,
                               isOn: Binding(get: { settings.showOverlay }, set: { settings.showOverlay = $0 }))
            }
            .padding(.top, 15)
        }
        .padding(.top, 16)
    }

    private var timer: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "自定义定时关闭", back: { page = .root })
            Picker("分钟", selection: $customMinutes) {
                ForEach(1...180, id: \.self) { minutes in
                    Text("\(minutes) 分钟").tag(minutes)
                }
            }
            .pickerStyle(.wheel)
            .environment(\.colorScheme, .dark)
            .frame(height: 150)
            Button {
                model.setSleepTimer(minutes: customMinutes)
                page = .root
            } label: {
                Text("确定")
                    .font(.system(size: PanelMetrics.titleSize, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Theme.pink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 15)
    }

    private var fit: some View {
        VStack(spacing: PanelMetrics.gap) {
            PanelHeader(title: "画面尺寸", back: { page = .root })
            ForEach(FitMode.allCases, id: \.self) { mode in
                PanelCardRow(title: mode.label, selected: settings.fit == mode) {
                    settings.fit = mode
                    page = .root
                }
            }
        }
        .padding(.top, 15)
    }

    private var sleepItems: [(value: SleepChoice, title: String)] {
        var custom = "自定义"
        if let minutes = model.sleepMinutes, Self.sleepChoice(for: minutes) == .custom {
            custom = "\(minutes)分钟"
        }
        return [(.off, "不开启"), (.minutes15, "15:00"), (.minutes30, "30:00"), (.minutes60, "60:00"), (.custom, custom)]
    }

    private var loopItems: [(value: LoopMode, title: String)] {
        [(LoopMode.single, "单集循环"), (LoopMode.list, "列表循环"), (LoopMode.none, "不循环")]
    }

    private func chooseSleep(_ choice: SleepChoice) {
        switch choice {
        case .off: model.setSleepTimer(minutes: nil)
        case .minutes15: model.setSleepTimer(minutes: 15)
        case .minutes30: model.setSleepTimer(minutes: 30)
        case .minutes60: model.setSleepTimer(minutes: 60)
        case .custom:
            customMinutes = model.sleepMinutes ?? customMinutes
            page = .timer
        }
    }

    private func setBTR(_ enabled: Bool) {
        settings.btrEnabled = enabled
        if let controller = model.controller {
            Task { await controller.setBTR(enabled) }
        }
    }

    private func startPiP() {
        model.startPiP()
        close()
    }

    private func watchLater() {
        Task {
            switch await model.addToWatchLater() {
            case .added:
                toast("已添加至稍后再看")
                close()
            case .needsLogin:
                close()
                requestLogin()
            case .failed(let message):
                toast(message)
            }
        }
    }
}

private struct PanelActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.panelText)
                    .frame(width: 48, height: 48)
                    .background(Theme.panelCard, in: RoundedRectangle(cornerRadius: PanelMetrics.groupRadius))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension VideoPageModel {
    enum WatchLaterResult: Equatable {
        case added, needsLogin
        case failed(String)
    }

    /// With no login cookies the client throws -101 before sending anything, so a logged-out tap needs no separate check.
    func addToWatchLater() async -> WatchLaterResult {
        guard let aid = detail?.aid else { return .failed("视频还没有加载完") }
        do {
            try await client.addToWatchLater(aid: aid)
            return .added
        } catch let error as BiliError where error.needsLogin {
            return .needsLogin
        } catch {
            return .failed(Self.message(for: error))
        }
    }
}
