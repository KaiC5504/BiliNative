import SwiftUI
import Danmaku

extension Theme {
    /// Sampled from the official 弹幕设置 panel (screenshots 07, 08 and 24).
    enum DanmakuPanel {
        static let track = panelRGB(0x424447)
        static let button = panelRGB(0x2C2E32)
        static let switchOff = panelRGB(0x2F3035)
        static let hairline = panelRGB(0x484C53)
        static let value = panelRGB(0xC9CCD0)
        static let cardRadius: CGFloat = 12
        static let rowInset: CGFloat = 16
    }
}

private func panelRGB(_ hex: UInt32) -> Color {
    Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

/// The 弹幕设置 panel: sliders and switches that write `AppSettings.danmaku`, which the renderer watches.
/// In landscape 添加屏蔽词 swaps this for `BlockWordsView` inside the panel; in portrait it pushes a page.
struct DanmakuSettingsPanel: View {
    var onNeedLogin: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @State private var expanded = false
    @State private var wordsInPanel = false
    @State private var wordsPushed = false

    private static let areaStops: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]
    private static let speedNames = ["极慢", "较慢", "适中", "较快", "极快"]
    private static let blockTypes: [BlockType] = [
        BlockType(name: "固定", icon: .fixed, key: \.blockFixed), BlockType(name: "滚动", icon: .scroll, key: \.blockScroll),
        BlockType(name: "彩色", icon: .colored, key: \.blockColored), BlockType(name: "高级", icon: .advanced, key: \.blockAdvanced),
        BlockType(name: "计数", icon: .count, key: \.blockCount),
    ]

    private struct BlockType: Identifiable {
        let name: String
        let icon: TypeIcon.Kind
        let key: WritableKeyPath<DanmakuFilterOptions, Bool>
        var id: String { name }
    }

    var body: some View {
        ZStack {
            settingsPage
                .opacity(wordsInPanel ? 0 : 1)
                .offset(x: wordsInPanel ? -32 : 0)
                .allowsHitTesting(!wordsInPanel)
                .accessibilityHidden(wordsInPanel)
            if wordsInPanel {
                BlockWordsView(appearance: .panel, onBack: { wordsInPanel = false }, onNeedLogin: onNeedLogin)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: wordsInPanel)
        .navigationDestination(isPresented: $wordsPushed) {
            BlockWordsView(appearance: .page, onNeedLogin: onNeedLogin)
        }
        .task {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "DemoScreen") {
            case "panel-danmaku-more": expanded = true
            case "block-words": wordsInPanel = true
            default: break
            }
            #endif
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                displayCard
                sectionTitle("画面防挡")
                avoidCard
                sectionTitle("更多工具")
                toolsCard
                resetButton
            }
            .padding(.top, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: sections

    private var header: some View {
        HStack {
            Text("弹幕设置")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.panelText)
            Spacer(minLength: 0)
            if !expanded {
                Button {
                    withAnimation(.smooth(duration: 0.3)) { expanded = true }
                } label: {
                    HStack(spacing: 3) {
                        Text("查看更多")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.panelSecondary)
                    .frame(height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 12)
    }

    private var displayCard: some View {
        PanelCard {
            SliderRow(title: "显示区域", valueText: percent(settings.area), position: areaPosition, stops: Self.areaStops.count)
            SliderRow(title: "不透明度", valueText: percent(settings.opacity), position: opacityPosition)
            if expanded {
                Hairline()
                SliderRow(title: "字体大小", valueText: percent(settings.scale), position: scalePosition)
                Hairline()
                SliderRow(title: "弹幕速度", valueText: Self.speedNames[speedIndex], position: speedPosition, stops: Self.speedNames.count)
            }
        }
    }

    private var avoidCard: some View {
        PanelCard {
            Text("按弹幕类型屏蔽")
                .font(.system(size: 12))
                .foregroundStyle(Theme.panelText)
                .padding(.top, 18)
                .padding(.horizontal, Theme.DanmakuPanel.rowInset)
            HStack(alignment: .top, spacing: 6.5) {
                ForEach(Self.blockTypes) { type in
                    TypeButton(name: type.name, icon: type.icon, blocked: filterBinding(type.key))
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 20)
            .padding(.horizontal, Theme.DanmakuPanel.rowInset)
            Hairline()
            ToggleRow(title: "重复弹幕隐藏", subtitle: "大量内容相同的弹幕会被隐藏", isOn: filterBinding(\.dedupe))
            Hairline()
            ToggleRow(title: "底部字幕区域防挡", subtitle: "底部弹幕会被隐藏", isOn: filterBinding(\.hideBottom))
        }
    }

    private var toolsCard: some View {
        PanelCard {
            ToggleRow(title: "弹幕观看屏蔽词", subtitle: "仅对我不展示特定弹幕", isOn: filterBinding(\.applyRules))
            Button(action: openBlockWords) {
                HStack {
                    Text("添加屏蔽词")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.panelText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.panelSecondary)
                }
                .padding(.horizontal, Theme.DanmakuPanel.rowInset)
                .frame(height: 35)
                .background(Theme.DanmakuPanel.button, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.DanmakuPanel.rowInset)
            .padding(.bottom, 16)
        }
    }

    private var resetButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { env.settings.danmaku = .defaults }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                Text("重置弹幕设置")
                    .font(.system(size: 14))
            }
            .foregroundStyle(Theme.panelText)
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 14)
        .padding(.bottom, 28)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.panelText)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }

    // MARK: settings access

    private var settings: DanmakuSettings { env.settings.danmaku }

    private func filterBinding(_ key: WritableKeyPath<DanmakuFilterOptions, Bool>) -> Binding<Bool> {
        Binding(get: { env.settings.danmaku.filter[keyPath: key] },
                set: { env.settings.danmaku.filter[keyPath: key] = $0 })
    }

    private var areaPosition: Binding<Double> {
        Binding(get: {
            let nearest = Self.areaStops.indices.min { abs(Self.areaStops[$0] - settings.area) < abs(Self.areaStops[$1] - settings.area) } ?? 0
            return Double(nearest) / Double(Self.areaStops.count - 1)
        }, set: {
            env.settings.danmaku.area = Self.areaStops[Int(($0 * Double(Self.areaStops.count - 1)).rounded())]
        })
    }

    private var opacityPosition: Binding<Double> {
        Binding(get: { (settings.opacity - 0.1) / 0.9 },
                set: { env.settings.danmaku.opacity = ((0.1 + $0 * 0.9) * 100).rounded() / 100 })
    }

    private var scalePosition: Binding<Double> {
        Binding(get: { (settings.scale - 0.5) / 1.5 },
                set: { env.settings.danmaku.scale = ((0.5 + $0 * 1.5) * 100).rounded() / 100 })
    }

    private var speedIndex: Int { min(max(settings.speed, 0), Self.speedNames.count - 1) }

    private var speedPosition: Binding<Double> {
        Binding(get: { Double(speedIndex) / Double(Self.speedNames.count - 1) },
                set: { env.settings.danmaku.speed = Int(($0 * Double(Self.speedNames.count - 1)).rounded()) })
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func openBlockWords() {
        guard case .loggedIn = env.account else {
            onNeedLogin()
            return
        }
        if OrientationController.shared.presentation == .inline {
            wordsPushed = true
        } else {
            wordsInPanel = true
        }
    }
}

// MARK: building blocks

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelCard, in: RoundedRectangle(cornerRadius: Theme.DanmakuPanel.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: Theme.DanmakuPanel.cardRadius))
    }
}

private struct Hairline: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Theme.DanmakuPanel.hairline)
            .frame(height: 1 / scale)
            .padding(.leading, Theme.DanmakuPanel.rowInset)
    }
}

private struct SliderRow: View {
    let title: String
    let valueText: String
    @Binding var position: Double
    var stops: Int? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.panelText)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.DanmakuPanel.value)
            }
            .padding(.horizontal, Theme.DanmakuPanel.rowInset)
            PanelSlider(position: $position, stops: stops)
                .padding(.horizontal, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityAdjustableAction { direction in
                    let step = stops.map { 1 / Double($0 - 1) } ?? 0.05
                    position = min(max(position + (direction == .increment ? step : -step), 0), 1)
                }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

/// The official slider: a 6 pt track, a thumb that overhangs its ends a little, and a dot per stop.
private struct PanelSlider: View {
    @Binding var position: Double
    var stops: Int?

    private let thumb: CGFloat = 13
    private let inset: CGFloat = 4
    private let trackHeight: CGFloat = 6
    private let dot: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let span = max(proxy.size.width - 2 * inset, 1)
            let thumbX = inset + span * position
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.DanmakuPanel.track)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Theme.pink)
                    .frame(width: thumbX, height: trackHeight)
                if let stops, stops > 1 {
                    ForEach(0..<stops, id: \.self) { index in
                        Circle()
                            .fill(.white)
                            .frame(width: dot, height: dot)
                            .offset(x: inset + span * Double(index) / Double(stops - 1) - dot / 2)
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .offset(x: thumbX - thumb / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                position = snapped(min(max((drag.location.x - inset) / span, 0), 1))
            })
        }
        .frame(height: 22)
        .animation(snapAnimation, value: position)
    }

    private var snapAnimation: Animation? {
        stops == nil ? nil : .smooth(duration: 0.15)
    }

    private func snapped(_ raw: Double) -> Double {
        guard let stops, stops > 1 else { return raw }
        return (raw * Double(stops - 1)).rounded() / Double(stops - 1)
    }
}

private struct SwitchGlyph: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.pink : Theme.DanmakuPanel.switchOff)
            .frame(width: 34, height: 20)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .offset(x: isOn ? 14 : 0)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.panelText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.panelSecondary)
                }
                Spacer(minLength: 0)
                SwitchGlyph(isOn: isOn)
            }
            .padding(.leading, Theme.DanmakuPanel.rowInset)
            .padding(.trailing, 15)
            .padding(.top, 17)
            .padding(.bottom, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "开" : "关")
        .accessibilityAddTraits(.isToggle)
    }
}

private struct TypeButton: View {
    let name: String
    let icon: TypeIcon.Kind
    @Binding var blocked: Bool

    var body: some View {
        Button { blocked.toggle() } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 13)
                    .fill(Theme.DanmakuPanel.button)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { TypeIcon(kind: icon, tint: tint) }
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("屏蔽\(name)弹幕")
        .accessibilityValue(blocked ? "已开启" : "已关闭")
        .accessibilityAddTraits(.isToggle)
    }

    private var tint: Color { blocked ? Theme.pink : Theme.panelText }
}

/// The five type glyphs: a rounded screen with a mark inside, drawn here because the official ones are not in the borrowed font.
private struct TypeIcon: View {
    enum Kind { case fixed, scroll, colored, advanced, count }

    let kind: Kind
    let tint: Color

    private let stroke: CGFloat = 1.5

    var body: some View {
        switch kind {
        case .colored:
            Image(systemName: "paintpalette")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(tint)
        case .count:
            screen.overlay {
                Text("×99")
                    .font(.system(size: 11, weight: .heavy).italic())
                    .foregroundStyle(tint)
            }
        default:
            screen.overlay { marks }
        }
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: 5)
            .stroke(tint, lineWidth: stroke)
            .frame(width: 26, height: 19)
    }

    private var marks: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(tint)
            func bar(_ from: CGFloat, _ to: CGFloat, y: CGFloat) {
                var path = Path()
                path.move(to: CGPoint(x: from, y: y))
                path.addLine(to: CGPoint(x: to, y: y))
                context.stroke(path, with: ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            func dot(_ x: CGFloat, y: CGFloat) {
                context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: ink)
            }
            func star(_ x: CGFloat, y: CGFloat) {
                var path = Path()
                for point in 0..<10 {
                    let radius: CGFloat = point.isMultiple(of: 2) ? 2.8 : 1.2
                    let angle = CGFloat(point) * .pi / 5 - .pi / 2
                    let spot = CGPoint(x: x + radius * cos(angle), y: y + radius * sin(angle))
                    if point == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
                }
                path.closeSubpath()
                context.fill(path, with: ink)
            }
            let midX = size.width / 2
            switch kind {
            case .fixed:
                dot(midX - 5, y: 6.5)
                bar(midX - 1.5, midX + 6.5, y: 6.5)
            case .scroll:
                dot(midX - 7.5, y: 6)
                bar(midX - 4, midX + 7, y: 6)
                dot(midX - 7.5, y: 11.5)
                bar(midX - 4, midX + 3, y: 11.5)
            case .advanced:
                star(midX - 7, y: 6)
                bar(midX - 3, midX + 7, y: 6)
                star(midX - 7, y: 12)
                bar(midX - 3, midX + 3, y: 12)
            default:
                break
            }
        }
        .frame(width: 26, height: 19)
    }
}
