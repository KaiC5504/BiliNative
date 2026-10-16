import SwiftUI

/// Sampled from the official app's dark input area (screenshots 22 and 23), which differs from the
/// light-page pink and the player panels.
enum DanmakuSendTheme {
    static let bar = Color(.sRGB, red: 0x24 / 255, green: 0x26 / 255, blue: 0x27 / 255)
    static let area = Color(.sRGB, red: 0x1A / 255, green: 0x1B / 255, blue: 0x1C / 255)
    static let accent = Color(.sRGB, red: 0xED / 255, green: 0x70 / 255, blue: 0x98 / 255)
    static let secondary = Color(.sRGB, red: 0x95 / 255, green: 0x99 / 255, blue: 0x9F / 255)
    static let placeholder = Color(.sRGB, red: 0xC9 / 255, green: 0xCC / 255, blue: 0xCF / 255)
    static let swatchRing = Color(.sRGB, red: 0x46 / 255, green: 0x49 / 255, blue: 0x4C / 255)
    static let vipLeading = Color(.sRGB, red: 0xD8 / 255, green: 0x96 / 255, blue: 0xD5 / 255)
    static let vipTrailing = Color(.sRGB, red: 0x7A / 255, green: 0xB2 / 255, blue: 0xE6 / 255)

    /// The keyboard's height in the official landscape shot, used until a real keyboard has been seen.
    static let landscapePanelHeight: CGFloat = 224
    static let portraitPanelHeight: CGFloat = 291

    static func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

/// 弹幕字号, 弹幕类型 and 弹幕颜色 (23). It fills the space of the keyboard it replaces.
struct DanmakuStylePanel: View {
    @Bindable var model: DanmakuSendModel
    let onVipOnly: () -> Void

    private static let colorNames = ["白色", "红色", "黄色", "绿色", "蓝色", "品红", "黄绿", "深蓝", "橙色", "紫色", "浅蓝", "橄榄"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row("弹幕字号") {
                option("默认", selected: model.style.fontSize == DanmakuStyle.defaultFontSize) {
                    SizeGlyph(fontSize: 15)
                } action: { model.style.fontSize = DanmakuStyle.defaultFontSize }
                option("较小", selected: model.style.fontSize == DanmakuStyle.smallFontSize) {
                    SizeGlyph(fontSize: 10)
                } action: { model.style.fontSize = DanmakuStyle.smallFontSize }
            }
            row("弹幕类型") {
                option("滚动", selected: model.style.mode == 1) { ModeGlyph(rows: [0.3, 0.55]) } action: { model.style.mode = 1 }
                option("置顶", selected: model.style.mode == 5) { ModeGlyph(rows: [0.3]) } action: { model.style.mode = 5 }
                option("置底", selected: model.style.mode == 4) { ModeGlyph(rows: [0.7]) } action: { model.style.mode = 4 }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    label("弹幕颜色")
                    HStack(spacing: 0) { swatches }
                        .padding(.leading, -13)
                }
                .frame(height: 54)
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    label("弹幕颜色")
                        .frame(height: 30)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(46), spacing: 0), count: 8), alignment: .leading, spacing: 4) {
                        swatches
                    }
                    .padding(.leading, -10)
                }
            }
        }
        .padding(.top, 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(DanmakuSendTheme.secondary)
            .frame(width: 64, alignment: .leading)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            label(title)
            content()
        }
        .frame(height: 54)
    }

    private func option<Icon: View>(_ title: String, selected: Bool, @ViewBuilder icon: () -> Icon,
                                    action: @escaping () -> Void) -> some View {
        let tint = selected ? DanmakuSendTheme.accent : DanmakuSendTheme.secondary
        return Button(action: action) {
            HStack(spacing: 7.7) {
                icon()
                    .frame(width: 21.7, height: 19.4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous).stroke(tint, lineWidth: 1.6)
                    }
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundStyle(tint)
            .frame(width: 94, height: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var swatches: some View {
        swatch(DanmakuStyle.colors[0], index: 0)
        vipChip
        ForEach(1..<DanmakuStyle.colors.count, id: \.self) { index in
            swatch(DanmakuStyle.colors[index], index: index)
        }
    }

    private func swatch(_ rgb: UInt32, index: Int) -> some View {
        let selected = !model.style.gradient && model.style.color == rgb
        return Button {
            model.style.color = rgb
            model.style.gradient = false
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(DanmakuSendTheme.swatchRing, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DanmakuSendTheme.color(rgb)).padding(2.4)
            }
            .frame(width: 26, height: 22.7)
            .overlay(alignment: .bottomTrailing) {
                if selected { CheckBadge().offset(x: 0.5, y: 0.5) }
            }
            .frame(width: 46, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.colorNames[index])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var vipChip: some View {
        Button {
            if model.vip {
                model.style.gradient = true
                model.style.color = 0xFFFFFF
            } else {
                onVipOnly()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [DanmakuSendTheme.vipLeading, DanmakuSendTheme.vipTrailing],
                                         startPoint: .leading, endPoint: .trailing))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4.5)
            }
            .frame(width: 26, height: 22.7)
            .overlay {
                Text("会员")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 9.6)
                    .background(DanmakuSendTheme.accent, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 0.5))
                    .offset(x: 8, y: -9)
            }
            .overlay(alignment: .bottomTrailing) {
                if model.style.gradient { CheckBadge().offset(x: 0.5, y: 0.5) }
            }
            .frame(width: 46, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("会员渐变色")
        .accessibilityAddTraits(model.style.gradient ? .isSelected : [])
    }
}

private struct CheckBadge: View {
    var body: some View {
        Circle()
            .fill(DanmakuSendTheme.accent)
            .overlay(Circle().stroke(.white, lineWidth: 1))
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 11, height: 11)
    }
}

private struct SizeGlyph: View {
    let fontSize: CGFloat

    var body: some View {
        Text("A")
            .font(.system(size: fontSize, weight: .medium))
    }
}

/// The lines of a danmaku in a screen: a dot and a dash per row.
private struct ModeGlyph: View {
    let rows: [CGFloat]

    var body: some View {
        Canvas { context, size in
            for row in rows {
                let y = size.height * row
                let dot = Path(ellipseIn: CGRect(x: size.width * 0.2, y: y - 0.9, width: 1.8, height: 1.8))
                context.fill(dot, with: .foreground)
                var dash = Path()
                dash.move(to: CGPoint(x: size.width * 0.38, y: y))
                dash.addLine(to: CGPoint(x: size.width * 0.78, y: y))
                context.stroke(dash, with: .foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }
}
