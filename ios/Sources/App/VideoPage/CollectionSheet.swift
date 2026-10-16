import SwiftUI
import AppLogic
import BiliAPI

/// Where the playing video sits in its 合集.
enum CollectionPosition {
    /// Its index among all episodes of every section. The cid decides first, since a 合集 may list several parts of
    /// one video; a later part of a listed video falls back to its bvid.
    static func index(of current: PlayItem?, in season: UgcSeason) -> Int? {
        guard let current else { return nil }
        let episodes = season.sections.flatMap(\.episodes)
        return episodes.firstIndex { $0.cid == current.cid } ?? episodes.firstIndex { $0.bvid == current.bvid }
    }

    /// "2/3" in the 合集 row.
    static func label(_ current: PlayItem?, in season: UgcSeason) -> String {
        let total = season.sections.reduce(0) { $0 + $1.episodes.count }
        guard let index = index(of: current, in: season) else { return "\(total)" }
        return "\(index + 1)/\(total)"
    }

    /// The section the sheet lists: the one holding the playing video, or the first.
    static func section(of current: PlayItem?, in season: UgcSeason) -> SeasonSection? {
        guard let index = index(of: current, in: season) else { return season.sections.first }
        var start = 0
        for section in season.sections {
            if index < start + section.episodes.count { return section }
            start += section.episodes.count
        }
        return season.sections.first
    }

    static func isPlaying(_ episode: SeasonEpisode, current: PlayItem?, in season: UgcSeason) -> Bool {
        guard let index = index(of: current, in: season) else { return false }
        let episodes = season.sections.flatMap(\.episodes)
        return episodes.indices.contains(index) && episodes[index] == episode
    }
}

/// "合集 · 名称" with the playing episode's place, opening the 合集 sheet (03).
struct CollectionRow: View {
    let season: UgcSeason
    let current: PlayItem?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("合集 · \(season.title)")
                    .font(Theme.Page.bodyFont)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Spacer(minLength: 12)
                PlayingBars(color: Theme.secondaryText)
                    .frame(width: 11, height: 12)
                Text(CollectionPosition.label(current, in: season))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(height: 35)
            .background(Theme.softGrey, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Metrics.gutter)
    }
}

/// The 合集 sheet (19): title, the intro with 展开, then 选集 with 正序/倒序 and the playing section's episodes.
/// The 收藏 pill and share button of the official sheet are left out.
struct CollectionSheet: View {
    let season: UgcSeason
    let current: PlayItem?
    let onChoose: (SeasonEpisode) -> Void
    let onClose: () -> Void
    @State private var introExpanded = false
    @State private var reversed = false

    var body: some View {
        PageSheetFrame(title: season.title, onClose: onClose) { dismiss in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !season.intro.isEmpty {
                        intro
                    }
                    HStack(spacing: 0) {
                        Text("选集")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        Button {
                            reversed.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "line.3.horizontal.decrease")
                                Text(reversed ? "倒序" : "正序")
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                    let episodes = CollectionPosition.section(of: current, in: season)?.episodes ?? []
                    ForEach(Array((reversed ? episodes.reversed() : episodes).enumerated()), id: \.element.cid) { position, episode in
                        EpisodeRow(episode: episode, playing: CollectionPosition.isPlaying(episode, current: current, in: season),
                                   showsDivider: position > 0) {
                            onChoose(episode)
                            dismiss()
                        }
                    }
                    Text("内容到底啦")
                        .font(Theme.Page.metaFont)
                        .foregroundStyle(Theme.Page.faintText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                .padding(.horizontal, Theme.Metrics.gutter)
            }
        }
    }

    @ViewBuilder
    private var intro: some View {
        if introExpanded {
            VStack(alignment: .leading, spacing: 4) {
                Text(season.intro)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("收起") { introExpanded = false }
                    .foregroundStyle(Theme.text)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 14))
        } else {
            ViewThatFits(in: .horizontal) {
                Text(season.intro)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 4) {
                    Text(season.intro)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    Button("展开") { introExpanded = true }
                        .foregroundStyle(Theme.text)
                        .buttonStyle(.plain)
                        .fixedSize()
                }
            }
            .font(.system(size: 14))
        }
    }
}

private struct EpisodeRow: View {
    let episode: SeasonEpisode
    let playing: Bool
    let showsDivider: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                VideoThumb(cover: episode.cover, duration: TimeFormat.clock(Double(episode.duration)), size: Theme.Page.episodeThumb)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if playing {
                            PlayingBars(color: Theme.pink)
                                .frame(width: 11, height: 13)
                        }
                        Text(episode.title)
                            .font(Theme.Page.bodyFont)
                            .foregroundStyle(playing ? Theme.pink : Theme.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Text(EpisodeDate.label(episode.pubdate))
                        .font(Theme.Page.metaFont)
                        .foregroundStyle(Theme.secondaryText)
                    VideoCounts(views: episode.views, danmaku: episode.danmaku)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.Page.episodeThumb.height, alignment: .leading)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(playing ? .isSelected : [])
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 0.5)
            }
        }
    }
}

/// "8月28日" this year, "2025年8月28日" before it.
enum EpisodeDate {
    static func label(_ unix: Int64, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: TimeInterval(unix))
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = "\(parts.month ?? 0)月\(parts.day ?? 0)日"
        return parts.year == calendar.component(.year, from: now) ? day : "\(parts.year ?? 0)年\(day)"
    }
}

/// Three bars of different heights, the official app's mark for what is playing.
struct PlayingBars: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bar = width * 0.22
            HStack(alignment: .bottom, spacing: (width - bar * 3) / 2) {
                Capsule().frame(width: bar, height: height)
                Capsule().frame(width: bar, height: height * 0.5)
                Capsule().frame(width: bar, height: height * 0.75)
            }
            .frame(width: width, height: height, alignment: .bottom)
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}

/// A white sheet over the page below the player (19). It is an overlay in the page, never a presented controller,
/// so rotation and picture in picture never see it.
struct PageSheetFrame<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: (_ dismiss: @escaping () -> Void) -> Content
    @State private var shown = false
    @State private var drag: CGFloat = 0
    @State private var closing = false

    private static var motion: Animation { .smooth(duration: 0.25) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Capsule()
                    .fill(Theme.Page.grabber)
                    .frame(width: 30, height: 3.5)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture()
                        .onChanged { drag = max(0, $0.translation.height) }
                        .onEnded { value in
                            if value.translation.height > 60 {
                                dismiss()
                            } else {
                                withAnimation(Self.motion) { drag = 0 }
                            }
                        })
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Page.tabText)
                            .frame(width: 24, height: 24)
                            .background(Theme.pageGrey, in: Circle())
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
                .padding(.leading, Theme.Metrics.gutter)
                .padding(.trailing, 6)
                content(dismiss)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: Theme.Page.sheetRadius, topTrailingRadius: Theme.Page.sheetRadius)
                    .fill(Theme.Page.background)
                    .shadow(color: Theme.Page.sheetShadow, radius: 6, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            }
            .offset(y: shown ? drag : geometry.size.height)
        }
        .onAppear {
            withAnimation(Self.motion) { shown = true }
        }
    }

    private func dismiss() {
        guard !closing else { return }
        closing = true
        withAnimation(Self.motion) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            onClose()
        }
    }
}
