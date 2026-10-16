import SwiftUI
import UIKit
import AppLogic
import BiliAPI

extension Theme {
    /// The action row under the title (03), measured at 3x.
    enum Actions {
        static let icon = Theme.Page.tabText
        static let count = Theme.Page.tabText
        static let iconSize: CGFloat = 24
        static let iconFont = Font.system(size: 23)
        static let countFont = Font.system(size: 12)
        static let ring: CGFloat = 40
        static let ringWidth: CGFloat = 2.5
        static let topPadding: CGFloat = 22
        static let bottomPadding: CGFloat = 2
    }
}

/// 点赞, 不喜欢, 投币, 收藏 and 分享 (03). Holding 点赞 fills rings around 点赞, 投币 and 收藏 and then gives all three.
struct ActionRow: View {
    let actions: ActionsModel
    /// 不喜欢 shows and does nothing until Task 23 brings the app token it needs.
    var onDislike: () -> Void = {}

    @State private var ring: Double = 0
    @State private var burst = 0
    @State private var hold: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            ActionCell(systemName: "hand.thumbsup.fill", active: actions.liked, label: "点赞", count: actions.likeCount)
                .tripleRing(progress: ring, burst: burst)
                .onTapGesture { Task { await actions.toggleLike() } }
                .onLongPressGesture(minimumDuration: TripleTiming.delay + TripleTiming.fill, maximumDistance: 24,
                                    perform: completeTriple, onPressingChanged: pressing)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "一键三连") { Task { await actions.triple() } }
            ActionCell(systemName: "hand.thumbsdown.fill", active: actions.disliked, label: "不喜欢", count: nil)
                .onTapGesture(perform: onDislike)
                .accessibilityAddTraits(.isButton)
            ActionCell(coin: true, active: actions.coins > 0, label: "投币", count: actions.coinCount)
                .tripleRing(progress: ring, burst: burst)
                .onTapGesture { actions.ask(.coin) }
                .accessibilityAddTraits(.isButton)
            ActionCell(systemName: "star.fill", active: actions.favorited, label: "收藏", count: actions.favCount)
                .tripleRing(progress: ring, burst: burst)
                .onTapGesture { actions.ask(.favourites) }
                .accessibilityAddTraits(.isButton)
            ActionCell(systemName: "arrowshape.turn.up.right.fill", active: false, label: "分享", count: actions.shareCount)
                .onTapGesture { actions.ask(.share) }
                .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.top, Theme.Actions.topPadding)
        .padding(.bottom, Theme.Actions.bottomPadding)
        .sensoryFeedback(.success, trigger: burst)
    }

    private func pressing(_ down: Bool) {
        hold?.cancel()
        guard down else {
            if ring > 0 {
                withAnimation(.easeOut(duration: 0.15)) { ring = 0 }
            }
            return
        }
        hold = Task {
            try? await Task.sleep(for: .seconds(TripleTiming.delay))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: TripleTiming.fill)) { ring = 1 }
        }
    }

    private func completeTriple() {
        hold?.cancel()
        burst += 1
        ring = 0
        Task { await actions.triple() }
    }
}

/// One column: the icon, pink and filled when on, over its count, or its name when there is none yet.
private struct ActionCell: View {
    var systemName = ""
    var coin = false
    let active: Bool
    let label: String
    let count: Int64?

    var body: some View {
        VStack(spacing: 7) {
            Group {
                if coin {
                    CoinGlyph(filled: true, tint: tint, ink: Theme.Page.background)
                        .frame(width: Theme.Actions.iconSize - 1, height: Theme.Actions.iconSize - 1)
                } else {
                    Image(systemName: systemName)
                        .font(Theme.Actions.iconFont)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: Theme.Actions.iconSize, height: Theme.Actions.iconSize)
            Text(text)
                .font(Theme.Actions.countFont)
                .foregroundStyle(active ? Theme.pink : Theme.Actions.count)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(count.map { CountFormat.short($0) } ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var tint: Color { active ? Theme.pink : Theme.Actions.icon }

    private var text: String {
        guard let count, count > 0 else { return label }
        return CountFormat.short(count)
    }
}

enum ShareLinks {
    /// `?p=N` for any part after the first, as the official app shares it.
    static func video(_ bvid: String, part: Int? = nil) -> URL {
        let base = "https://www.bilibili.com/video/\(bvid)"
        let string = part.map { $0 > 1 ? "\(base)?p=\($0)" : base } ?? base
        return URL(string: string) ?? URL(string: "https://www.bilibili.com")!
    }
}

/// The iOS share sheet, presented from UIKit because SwiftUI's ShareLink does not say whether the share went out,
/// and a completed share is counted.
@MainActor
enum SharePresenter {
    static func present(title: String, url: URL, in window: UIWindow? = nil, completion: @escaping (Bool) -> Void) {
        guard let window = window ?? keyWindow, var top = window.rootViewController else { return completion(false) }
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let sheet = UIActivityViewController(activityItems: [title, url], applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}
