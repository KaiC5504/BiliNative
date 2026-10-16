import SwiftUI
import UIKit
import BiliAPI

/// The emote panel under the composer (14): 最近使用 on the first package, 所有表情 for the selected one, and the
/// package tabs along the bottom. Text (颜文字) packages show their emotes as text.
struct EmotePanel: View {
    let packages: [EmotePackage]
    let recent: [Emote]
    let bottomInset: CGFloat
    /// Nil while the packages are loading; set once loading failed.
    let onRetry: (() -> Void)?
    let onPick: (Emote) -> Void

    @State private var selection: Int64?

    private typealias T = Theme.Composer

    private var selected: EmotePackage? {
        packages.first { $0.id == selection } ?? packages.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let selected {
                    ScrollView {
                        content(selected)
                    }
                    .scrollIndicators(.hidden)
                    .id(selected.id)
                } else if let onRetry {
                    Button(action: onRetry) {
                        Text("表情加载失败，点击重试")
                            .font(T.sectionFont)
                            .foregroundStyle(T.sectionTitle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: T.panelHeight)
            .background(T.panel)
            tabs
            T.tabBar
                .frame(height: bottomInset)
        }
    }

    @ViewBuilder
    private func content(_ package: EmotePackage) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if package.id == packages.first?.id, !recent.isEmpty {
                section("最近使用")
                grid(recent, columns: T.columns, rowHeight: T.recentRow, side: T.emote)
            }
            section("所有表情")
            if package.isText {
                grid(package.emotes, columns: T.textColumns, rowHeight: T.textRow, side: 0)
            } else if package.emotes.contains(where: \.large) {
                grid(package.emotes, columns: T.largeColumns, rowHeight: T.largeRow, side: T.largeEmote)
            } else {
                grid(package.emotes, columns: T.columns, rowHeight: T.row, side: T.emote)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(T.sectionFont)
            .foregroundStyle(T.sectionTitle)
            .padding(.leading, Theme.Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: T.sectionHeight)
    }

    private func grid(_ emotes: [Emote], columns: Int, rowHeight: CGFloat, side: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 0) {
            ForEach(Array(emotes.enumerated()), id: \.offset) { _, emote in
                Button {
                    onPick(emote)
                } label: {
                    cell(emote, side: side)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emote.token)
            }
        }
        .padding(.horizontal, T.gridSide)
    }

    @ViewBuilder
    private func cell(_ emote: Emote, side: CGFloat) -> some View {
        if emote.url.isEmpty {
            Text(emote.token)
                .font(T.kaomojiFont)
                .foregroundStyle(T.kaomoji)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
        } else {
            EmoteImage(url: emote.url)
                .frame(width: side, height: side)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(packages, id: \.id) { package in
                    Button {
                        selection = package.id
                    } label: {
                        tabLabel(package)
                            .frame(width: T.tabWidth, height: T.tabHeight)
                            .background(package.id == selected?.id ? T.tabSelected : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(package.name)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: T.tabHeight)
        .background(T.tabBar)
    }

    @ViewBuilder
    private func tabLabel(_ package: EmotePackage) -> some View {
        if package.isText || package.icon.isEmpty {
            Text(package.isText ? package.emotes.first?.token ?? package.name : package.name)
                .font(T.kaomojiTabFont)
                .foregroundStyle(T.kaomojiTab)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
        } else {
            EmoteImage(url: package.icon)
                .frame(width: T.tabIcon, height: T.tabIcon)
        }
    }
}

/// One emote picture through the shared image cache; nothing is drawn until it arrives.
struct EmoteImage: View {
    let url: String
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .task(id: url) {
                guard let address = ImageLoader.secureURL(url) else { return }
                image = await ImageLoader.shared.image(for: address)
            }
    }
}
