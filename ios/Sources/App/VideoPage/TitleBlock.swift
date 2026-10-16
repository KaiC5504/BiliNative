import SwiftUI
import AppLogic
import BiliAPI

/// The title with its 活动 tag and ⌄, and the meta line (03). Expanded (18) it adds the BV id, the reprint notice,
/// the description and the tags.
struct TitleBlock: View {
    let detail: VideoDetail
    let online: String?
    let tags: [VideoTag]
    @Binding var expanded: Bool
    let onRun: (RichRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if detail.honor != nil {
                        Text("活动")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.pink)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Theme.softGrey, in: Capsule())
                    }
                    Text(detail.title)
                        .font(Theme.Page.titleFont)
                        .foregroundStyle(Theme.text)
                        .lineLimit(expanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "收起简介" : "展开简介")

            meta
                .padding(.top, 8)

            if expanded {
                details
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Metrics.gutter)
    }

    private var meta: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.rectangle")
            Text(CountFormat.short(detail.stat.view))
            Image(systemName: "list.bullet.rectangle")
                .padding(.leading, 8)
            Text(CountFormat.short(detail.stat.danmaku))
            Text(TimeFormat.publish(detail.pubdate))
                .padding(.leading, 8)
            if let online, !online.isEmpty {
                Image(systemName: "person.2")
                    .padding(.leading, 8)
                Text("\(online)人正在看")
            }
        }
        .font(Theme.Page.metaFont)
        .foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(detail.bvid)
                    .textSelection(.enabled)
                if detail.copyright == 1 {
                    Image(systemName: "nosign")
                        .foregroundStyle(Theme.Page.forbidden)
                        .padding(.leading, 8)
                    Text("未经作者授权禁止转载")
                }
            }
            .font(Theme.Page.metaFont)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)

            let runs = Self.descriptionRuns(detail.descParts)
            if !runs.isEmpty {
                DescriptionText(runs: runs, onRun: onRun)
                    .padding(.top, 6)
            }

            let plain = tags.filter { $0.kind == .normal }
            if !plain.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(plain, id: \.id) { tag in
                        TagChip(tag: tag)
                    }
                }
                .padding(.top, 14)
            }
        }
    }

    /// Mentions come from `desc_v2`'s typed parts; timestamps, video ids and links are found in the plain parts.
    static func descriptionRuns(_ parts: [DescPart]) -> [RichRun] {
        parts.flatMap { part -> [RichRun] in
            if let mid = part.mentionMid { return [.mention(name: part.text, mid: mid)] }
            return RichText.runs(part.text, emotes: [:], mentions: [:], links: [:])
        }
    }
}

struct DescriptionText: View {
    let runs: [RichRun]
    let onRun: (RichRun) -> Void

    var body: some View {
        Text(RichLink.attributed(runs, linkColor: Theme.link))
            .font(Theme.Page.metaFont)
            .foregroundStyle(Theme.secondaryText)
            .tint(Theme.link)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard let run = RichLink.run(for: url) else { return .systemAction }
                onRun(run)
                return .handled
            })
    }
}

/// A tag, the BGM or a topic. They lead nowhere until there is a search page, so they are not buttons.
struct TagChip: View {
    let tag: VideoTag

    var body: some View {
        HStack(spacing: 5) {
            switch tag.kind {
            case .bgm:
                Image(systemName: "music.note")
            case .topic:
                Image(systemName: "number.square")
            case .normal:
                EmptyView()
            }
            Text(tag.name)
                .lineLimit(1)
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.Page.chipText)
        .padding(.horizontal, 12)
        .frame(height: Theme.Page.chipHeight)
        .background(Theme.softGrey, in: Capsule())
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
