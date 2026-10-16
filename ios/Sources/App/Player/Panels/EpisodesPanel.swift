import SwiftUI
import AppLogic
import BiliAPI

/// 选集: the parts of a multi-part video, or else the 合集 section holding the playing episode.
struct EpisodesPanel: View {
    let model: VideoPageModel
    let close: () -> Void

    struct Row: Identifiable, Equatable {
        let id: String
        let title: String
        let duration: String?
        let selected: Bool
        let item: PlayItem
        /// A part plays in place; an episode is another video and goes through `switchTo`.
        let isPart: Bool
    }

    static func rows(detail: VideoDetail, current: PlayItem?) -> [Row] {
        if detail.pages.count > 1 {
            return detail.pages.map { page in
                let item = PlayItem(bvid: detail.bvid, cid: page.cid)
                return Row(id: "p\(page.cid)", title: "P\(page.page) \(page.part)", duration: TimeFormat.clock(Double(page.duration)),
                           selected: item == current, item: item, isPart: true)
            }
        }
        guard let season = detail.season else { return [] }
        let section = season.sections.first { $0.episodes.contains { $0.bvid == detail.bvid } } ?? season.sections.first
        return (section?.episodes ?? []).map { episode in
            Row(id: "e\(episode.bvid)-\(episode.cid)", title: episode.title, duration: TimeFormat.clock(Double(episode.duration)),
                selected: episode.bvid == current?.bvid, item: PlayItem(bvid: episode.bvid, cid: episode.cid), isPart: false)
        }
    }

    var body: some View {
        let rows = model.detail.map { Self.rows(detail: $0, current: model.current) } ?? []
        VStack(spacing: PanelMetrics.gap) {
            PanelHeader(title: "选集")
            ForEach(rows) { row in
                PanelCardRow(title: row.title, detail: row.duration, selected: row.selected) { choose(row) }
            }
        }
        .padding(.top, 15)
    }

    private func choose(_ row: Row) {
        defer { close() }
        guard !row.selected else { return }
        Task {
            if row.isPart {
                await model.play(row.item, at: nil)
            } else {
                await model.switchTo(row.item)
            }
        }
    }
}
