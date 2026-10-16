import SwiftUI
import UIKit

extension Theme {
    static let panelHairline = Color.white.opacity(0.12)
    static let panelTrackOff = Color.white.opacity(0.18)
}

/// Sizes read off the official app's landscape panels (05, 06, 20, 21) in points.
enum PanelMetrics {
    static let rowRadius: CGFloat = 8
    static let groupRadius: CGFloat = 10
    static let cardHeight: CGFloat = 54
    static let rowHeight: CGFloat = 51
    static let gap: CGFloat = 8
    static let trailingMargin: CGFloat = 16
    static let titleSize: CGFloat = 14
    static let iconInset: CGFloat = 17
    static let labelInset: CGFloat = 44
}

private struct PanelLandscapeKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True when the panel sits at the right of a landscape screen, false in the portrait bottom sheet.
    var panelLandscape: Bool {
        get { self[PanelLandscapeKey.self] }
        set { self[PanelLandscapeKey.self] = newValue }
    }
}

enum PanelInsets {
    /// The panel layer ignores the safe area to cover the whole screen, so SwiftUI reports no insets inside it.
    @MainActor static var window: UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets ?? .zero
    }
}

/// A right-side panel in landscape and a bottom sheet in portrait, over the page. Tapping outside it dismisses.
/// It is an overlay in the page, never a presented controller, so rotation and picture in picture never see it.
struct SidePanel<Content: View>: View {
    enum Style {
        /// A dark panel on the right edge; the fraction is of the screen width.
        case side(width: CGFloat)
        /// No panel: the content floats as a column on the dimmed video (the 倍速 picker).
        case column
    }

    let identifier: String
    let style: Style
    let portraitHeight: CGFloat
    let dismiss: () -> Void
    let content: () -> Content

    /// The slide and fade are driven by this flag instead of insertion transitions: a transition fades the dismiss
    /// layer's UIKit host to alpha 0, and a re-opened panel then kept that host invisible to touches.
    @State private var shown = false
    @State private var closer: Task<Void, Never>?

    init(identifier: String, style: Style = .side(width: 0.4), portraitHeight: CGFloat = 0.62,
         dismiss: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.identifier = identifier
        self.style = style
        self.portraitHeight = portraitHeight
        self.dismiss = dismiss
        self.content = content
    }

    private static var motion: Animation { .smooth(duration: 0.25) }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let insets = PanelInsets.window
            ZStack(alignment: landscape ? .trailing : .bottom) {
                TapCatcher(onTap: requestDismiss)
                if landscape {
                    switch style {
                    case .side(let fraction):
                        side(width: geometry.size.width * fraction, insets: insets)
                    case .column:
                        column(in: geometry.size, insets: insets)
                    }
                } else {
                    sheet(height: geometry.size.height * portraitHeight, insets: insets)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .environment(\.panelLandscape, landscape)
        }
        .onAppear {
            withAnimation(Self.motion) { shown = true }
        }
        .onDisappear {
            closer?.cancel()
        }
    }

    /// Slides out, then lets go of the binding.
    private func requestDismiss() {
        guard closer == nil else { return }
        withAnimation(Self.motion) { shown = false }
        closer = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private func side(width: CGFloat, insets: UIEdgeInsets) -> some View {
        ScrollView(showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom + 16)
                .padding(.trailing, insets.right + PanelMetrics.trailingMargin)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .contentShape(Rectangle())
        .onTapGesture {}
        .background(PanelProbe(identifier: identifier))
        .accessibilityIdentifier(identifier)
        .offset(x: shown ? 0 : width)
    }

    /// The 倍速 column: a transparent strip at the right edge with the content centred in it, over a dimmed screen.
    private func column(in size: CGSize, insets: UIEdgeInsets) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(shown ? 0.4 : 0)
                .allowsHitTesting(false)
            // A scroll view, like the side panel's, so UIKit hit testing resolves a touch on the strip to it and not to the
            // dismiss layer underneath; SwiftUI gestures alone do not stop that.
            ScrollView(showsIndicators: false) {
                content()
                    .padding(.trailing, insets.right + PanelMetrics.trailingMargin)
                    .frame(minHeight: size.height)
            }
            .frame(width: size.width * 0.28, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture {}
            .opacity(shown ? 1 : 0)
                .background(PanelProbe(identifier: identifier))
                .accessibilityIdentifier(identifier)
        }
    }

    private func sheet(height: CGFloat, insets: UIEdgeInsets) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(shown ? 0.4 : 0)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onEnded { drag in
                        if drag.translation.height > 40 { requestDismiss() }
                    })
                ScrollView(showsIndicators: false) {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metrics.gutter)
                        .padding(.bottom, insets.bottom + 12)
                }
            }
            .frame(height: height, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(Theme.panel, in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture {}
            .background(PanelProbe(identifier: identifier))
            .accessibilityIdentifier(identifier)
            .offset(y: shown ? 0 : height + insets.bottom)
        }
    }
}

/// The full-screen layer behind a panel. A UIKit view so a test can find it, hit test the screen and fire it.
struct TapCatcher: UIViewRepresentable {
    let onTap: () -> Void

    func makeUIView(context: Context) -> TapCatcherView {
        let view = TapCatcherView()
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: TapCatcherView, context: Context) {
        view.onTap = onTap
    }
}

final class TapCatcherView: UIView {
    static let identifier = "panel.dismiss"

    var onTap: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityIdentifier = Self.identifier
        accessibilityLabel = "关闭"
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() {
        onTap()
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }
}

/// An invisible UIView carrying the panel's accessibility identifier: SwiftUI's own identifiers only exist in the
/// accessibility tree, which a unit test cannot walk, while this one is in the view hierarchy.
struct PanelProbe: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = identifier
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = identifier
    }
}

// MARK: shared pieces

struct PanelHeader<Trailing: View>: View {
    let title: String
    let back: (() -> Void)?
    let trailing: Trailing

    init(title: String, back: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.back = back
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 6) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.panelText)
                        .frame(width: 24, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
            }
            Text(title)
                .font(.system(size: PanelMetrics.titleSize))
                .foregroundStyle(Theme.panelText)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 30)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, back: (() -> Void)? = nil) {
        self.init(title: title, back: back) { EmptyView() }
    }
}

struct PanelTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: PanelMetrics.titleSize))
            .foregroundStyle(Theme.panelText)
    }
}

/// One dark rounded card per option, as in the 清晰度 list.
struct PanelCardRow: View {
    let title: String
    var subtitle: String?
    var badge: String?
    var detail: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: PanelMetrics.titleSize))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .frame(height: 14)
                                .background(Theme.pink, in: Capsule())
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.panelSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.panelSecondary)
                }
            }
            .foregroundStyle(selected ? Theme.pink : Theme.panelText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: PanelMetrics.cardHeight, alignment: .leading)
            .background(Theme.panelCard, in: RoundedRectangle(cornerRadius: PanelMetrics.rowRadius))
            .contentShape(RoundedRectangle(cornerRadius: PanelMetrics.rowRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PanelGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Theme.panelCard, in: RoundedRectangle(cornerRadius: PanelMetrics.groupRadius))
    }
}

/// An icon, a label and whatever sits at the right, 51 pt tall with the hairline the official card draws under it.
struct PanelRowFrame<Trailing: View>: View {
    let icon: String
    let title: String
    var showsDivider = true
    let trailing: Trailing

    init(icon: String, title: String, showsDivider: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.title = title
        self.showsDivider = showsDivider
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: PanelMetrics.iconInset)
            Text(title)
                .font(.system(size: PanelMetrics.titleSize))
                .lineLimit(1)
                .fixedSize()
            trailing
        }
        .foregroundStyle(Theme.panelText)
        .padding(.leading, PanelMetrics.iconInset)
        .padding(.trailing, 15)
        .frame(height: PanelMetrics.rowHeight)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.panelHairline)
                    .frame(height: 0.5)
                    .padding(.leading, PanelMetrics.labelInset)
            }
        }
    }
}

struct PanelToggleRow: View {
    let icon: String
    let title: String
    var showsDivider = true
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            PanelRowFrame(icon: icon, title: title, showsDivider: showsDivider) {
                Spacer(minLength: 8)
                PanelSwitch(isOn: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "开" : "关")
        .accessibilityAddTraits(.isButton)
    }
}

/// The official switch is smaller than UIKit's (33 by 20 pt), with a pink track.
struct PanelSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.pink : Theme.panelTrackOff)
            .frame(width: 33, height: 20)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .offset(x: isOn ? 13 : 0)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
    }
}

struct PanelSegments<Value: Equatable>: View {
    let items: [(value: Value, title: String)]
    let selection: Value
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.panelHairline)
                        .frame(width: 0.5, height: 20)
                }
                let selected = item.value == selection
                Button {
                    select(item.value)
                } label: {
                    Text(item.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Theme.pink : Theme.panelText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
