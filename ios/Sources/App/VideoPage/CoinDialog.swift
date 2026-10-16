import SwiftUI
import UIKit

extension Theme {
    /// The 投币 dialog (15), measured at 3x on the 440 pt wide reference.
    enum Coin {
        static let dim = Color.black.opacity(0.62)
        static let text = Color.white
        /// The crates drawn when the borrowed art is missing.
        static let crate = Color(.sRGB, red: 0xC6 / 255, green: 0x8A / 255, blue: 0x55 / 255)
        static let crateEdge = Color(.sRGB, red: 0x9C / 255, green: 0x5B / 255, blue: 0x33 / 255)
        static let disabledArrow = Color.white.opacity(0.35)

        static let card: CGFloat = 71
        static let selectedCard: CGFloat = 86
        /// Between the centres of the two crates.
        static let cardSpacing: CGFloat = 114
        static let arrow = CGSize(width: 14, height: 24)
        static let arrowInset: CGFloat = 16
        static let mascotGap: CGFloat = 46
        static let mascotHeight: CGFloat = 130
        static let hintGap: CGFloat = 20
        static let close: CGFloat = 30
        static let bottomInset: CGFloat = 17
        static let bottomRow: CGFloat = 44
        /// Where the crates' centre sits in portrait, as a share of the screen height.
        static let cardsCentre: CGFloat = 0.497
        /// The column landscape scales to the screen height.
        static let columnWidth: CGFloat = 440
        static let columnGap: CGFloat = 20
        /// The lightning art is a 1080 pt wide frame around a 225 pt crate.
        static let thunderWidth: CGFloat = 1080 / 225
        static let hintFont = Font.system(size: 15)
        static let bottomFont = Font.system(size: 15)
        static let labelFont = Font.system(size: 13, weight: .heavy)
    }
}

/// 投币 (15): two crates, 1 and 2 硬币, the mascot that throws, the balance, 同时点赞内容 and ✕. An overlay in the page,
/// never a presented controller, so rotation never sees it.
struct CoinDialog: View {
    static let identifier = "dialog.coin"
    static let helpURL = URL(string: "https://www.bilibili.com/blackboard/help.html")!

    let actions: ActionsModel
    let balance: Double?
    var onClose: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var selection = 2
    @State private var shown = false
    @State private var throwing = false
    @State private var flight: CGFloat = 0
    @State private var thunder = 0
    @State private var closing = false

    private static let art = Art()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let landscape = size.width > size.height
            let insets = PanelInsets.window
            ZStack {
                Theme.Coin.dim
                    .allowsHitTesting(false)
                TapCatcher(onTap: dismiss)
                if landscape {
                    let natural = stageHeight + Theme.Coin.columnGap + Theme.Coin.bottomRow
                    let scale = min(1, (size.height - insets.top - insets.bottom - 16) / natural)
                    VStack(spacing: Theme.Coin.columnGap) {
                        stage(width: Theme.Coin.columnWidth)
                        bottomRow
                    }
                    .frame(width: Theme.Coin.columnWidth)
                    .scaleEffect(scale)
                    .frame(width: size.width, height: size.height)
                } else {
                    VStack(spacing: 0) {
                        stage(width: size.width)
                            .padding(.top, size.height * Theme.Coin.cardsCentre - Theme.Coin.selectedCard / 2)
                        Spacer(minLength: 0)
                        bottomRow
                            .padding(.bottom, insets.bottom + 6)
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
            .opacity(shown ? 1 : 0)
        }
        .background(PanelProbe(identifier: Self.identifier))
        .sensoryFeedback(.impact(weight: .medium), trigger: throwing) { _, now in now }
        .onAppear {
            selection = available.last ?? 1
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
        }
        .onChange(of: balance) {
            if !canThrow(selection) { selection = available.last ?? selection }
        }
    }

    // MARK: layout

    private var stageHeight: CGFloat {
        Theme.Coin.selectedCard + Theme.Coin.mascotGap + Theme.Coin.mascotHeight + Theme.Coin.hintGap + 44
    }

    /// The crates, the mascot and the two lines under it.
    private func stage(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            cards(width: width)
                .zIndex(1)
            mascot
                .padding(.top, Theme.Coin.mascotGap)
            VStack(spacing: 4) {
                Text(notEnough ? "硬币不足" : "上滑或点击22娘投硬币")
                Text("硬币余额：\(balance.map { String(format: "%.1f", $0) } ?? "--")")
            }
            .font(Theme.Coin.hintFont)
            .foregroundStyle(Theme.Coin.text)
            .padding(.top, Theme.Coin.hintGap)
        }
        .frame(width: width, height: stageHeight, alignment: .top)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 16).onEnded(swiped))
        .hitTestable(height: stageHeight)
    }

    private func cards(width: CGFloat) -> some View {
        ZStack {
            ForEach([1, 2], id: \.self) { multiply in
                let selected = multiply == selection
                CoinCard(multiply: multiply, selected: selected, enabled: canThrow(multiply), flight: selected ? flight : 0,
                         thunder: selected ? thunder : 0, art: Self.art)
                    .offset(x: CGFloat(multiply - selection) * Theme.Coin.cardSpacing)
                    .onTapGesture { tapped(multiply) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(multiply) 硬币")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            HStack {
                arrow(left: true, enabled: selection == 2 && canThrow(1)) { choose(1) }
                Spacer(minLength: 0)
                arrow(left: false, enabled: selection == 1 && canThrow(2)) { choose(2) }
            }
            .padding(.horizontal, Theme.Coin.arrowInset)
        }
        .frame(width: width, height: Theme.Coin.selectedCard)
        .animation(.spring(duration: 0.3), value: selection)
    }

    private func arrow(left: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let image = Self.art.arrow(left: left, enabled: enabled) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: left ? "chevron.left" : "chevron.right")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(enabled ? Theme.Coin.text : Theme.Coin.disabledArrow)
                }
            }
            .frame(width: Theme.Coin.arrow.width, height: Theme.Coin.arrow.height)
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(left ? "1 硬币" : "2 硬币")
    }

    @ViewBuilder
    private var mascot: some View {
        let image = notEnough ? Self.art.notEnough : Self.art.mascot
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .onTapGesture(perform: throwCoin)
                    .accessibilityLabel("投币")
                    .accessibilityAddTraits(.isButton)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Coin.mascotHeight)
        .offset(y: shown && !closing ? 0 : 420)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: shown)
        .animation(.easeIn(duration: 0.2), value: closing)
    }

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button {
                env.settings.coinAlsoLike.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: env.settings.coinAlsoLike ? "checkmark.square" : "square")
                        .font(.system(size: 18))
                    Text("同时点赞内容")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(env.settings.coinAlsoLike ? .isSelected : [])
            Spacer(minLength: 8)
            Button {
                openURL(Self.helpURL)
            } label: {
                Text("如何获取硬币？")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(Theme.Coin.bottomFont)
        .foregroundStyle(Theme.Coin.text)
        .overlay {
            Button(action: dismiss) {
                Group {
                    if let close = Self.art.close {
                        Image(uiImage: close).resizable().scaledToFit()
                    } else {
                        Image(systemName: "xmark.circle")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.light)
                            .foregroundStyle(Theme.Coin.text)
                    }
                }
                .frame(width: Theme.Coin.close, height: Theme.Coin.close)
                .padding(7)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, Theme.Coin.bottomInset)
        .frame(height: Theme.Coin.bottomRow)
        .hitTestable(height: Theme.Coin.bottomRow)
    }

    // MARK: choosing and throwing

    private var notEnough: Bool { (balance ?? 1) < 1 }

    private func canThrow(_ multiply: Int) -> Bool {
        if let balance { return actions.canGive(multiply, balance: balance) }
        return multiply >= 1 && multiply <= actions.maxCoins
    }

    private var available: [Int] { [1, 2].filter(canThrow) }

    private func choose(_ multiply: Int) {
        guard !throwing, canThrow(multiply) else { return }
        selection = multiply
    }

    private func tapped(_ multiply: Int) {
        if multiply == selection { throwCoin() } else { choose(multiply) }
    }

    private func swiped(_ drag: DragGesture.Value) {
        let dx = drag.translation.width
        let dy = drag.translation.height
        if abs(dx) > abs(dy), abs(dx) > 40 {
            choose(dx < 0 ? 2 : 1)
        } else if dy < -50, abs(dy) > abs(dx) {
            throwCoin()
        }
    }

    /// The coin flies up while the lightning plays on the crate; the request goes out once the dialog has closed.
    private func throwCoin() {
        guard !throwing, !closing, canThrow(selection) else { return }
        throwing = true
        let multiply = selection
        let alsoLike = env.settings.coinAlsoLike
        withAnimation(.easeIn(duration: 0.35)) { flight = 1 }
        Task {
            for frame in 1...3 {
                thunder = frame
                try? await Task.sleep(for: .milliseconds(90))
            }
            thunder = 0
            try? await Task.sleep(for: .milliseconds(80))
            let actions = self.actions
            Task { await actions.coin(multiply, alsoLike: alsoLike) }
            dismiss()
        }
    }

    private func dismiss() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            onClose()
        }
    }

    /// The borrowed PNGs, read once. Nil members mean the art is not in the bundle.
    struct Art {
        let box = BorrowedIcon.art("ic_pay_coins_box")
        let coins = [BorrowedIcon.art("ic_coins_one"), BorrowedIcon.art("ic_coins_two")]
        let mascot = BorrowedIcon.art("ic_22_gun_sister")
        let notEnough = BorrowedIcon.art("ic_22_not_enough_pay")
        let close = BorrowedIcon.art("ic_panel_close")
        let thunder = [BorrowedIcon.art("ic_thunder_1"), BorrowedIcon.art("ic_thunder_2"), BorrowedIcon.art("ic_thunder_3")]
        private let arrows = [BorrowedIcon.art("ic_left"), BorrowedIcon.art("ic_left_disable"),
                              BorrowedIcon.art("ic_right"), BorrowedIcon.art("ic_right_disable")]

        func arrow(left: Bool, enabled: Bool) -> UIImage? {
            arrows[(left ? 0 : 2) + (enabled ? 0 : 1)]
        }

        func coin(_ multiply: Int) -> UIImage? {
            coins[multiply == 1 ? 0 : 1]
        }
    }
}

/// One crate: the borrowed box with its coin and label, or a plain brown square with an SF Symbol without the art.
private struct CoinCard: View {
    let multiply: Int
    let selected: Bool
    let enabled: Bool
    /// 0 at rest, 1 once the coin has flown off the top.
    let flight: CGFloat
    /// The lightning frame showing, 1 to 3, or 0.
    let thunder: Int
    let art: CoinDialog.Art

    var body: some View {
        let side = selected ? Theme.Coin.selectedCard : Theme.Coin.card
        ZStack {
            if let box = art.box, let coin = art.coin(multiply) {
                Image(uiImage: box).resizable()
                Image(uiImage: coin)
                    .resizable()
                    .scaledToFit()
                    .frame(height: side * 0.63)
                    .offset(y: side * 0.02 - flight * 320)
                    .opacity(1 - flight)
            } else {
                RoundedRectangle(cornerRadius: side * 0.14)
                    .fill(Theme.Coin.crate)
                    .overlay {
                        RoundedRectangle(cornerRadius: side * 0.14)
                            .strokeBorder(Theme.Coin.crateEdge, lineWidth: 3)
                    }
                VStack(spacing: side * 0.05) {
                    Image(systemName: "bitcoinsign.circle")
                        .font(.system(size: side * 0.36))
                        .offset(y: -flight * 320)
                        .opacity(1 - flight)
                    Text("\(multiply) 硬币")
                        .font(Theme.Coin.labelFont)
                }
                .foregroundStyle(Theme.Coin.text)
            }
        }
        .frame(width: side, height: side)
        .overlay {
            if thunder > 0, let frame = art.thunder[thunder - 1] {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side * Theme.Coin.thunderWidth)
                    .allowsHitTesting(false)
            }
        }
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Wraps the view in a scroll view that never scrolls. UIKit hit testing lands on SwiftUI content only through a
    /// UIKit view, so without one a tap here would reach the dismiss layer underneath.
    func hitTestable(height: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) { self }
            .scrollDisabled(true)
            .scrollClipDisabled()
            .frame(height: height)
    }
}
