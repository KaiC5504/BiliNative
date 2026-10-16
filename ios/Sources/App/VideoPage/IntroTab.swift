import SwiftUI
import AppLogic
import BiliAPI

/// 简介 (03, 18): the uploader, the title and stats, the action row, 合集 or 分P, the topic and BGM chips, and the
/// related videos.
struct IntroTab<Actions: View>: View {
    let model: VideoPageModel
    let state: PageTabsState
    /// 关注 belongs to the actions (Task 21). Until they are wired the pill shows the uploader card's state.
    var following: Bool?
    var onFollow: () -> Void = {}
    let onNeedLogin: () -> Void
    /// The action row's place, between the title block and 合集.
    @ViewBuilder let actions: () -> Actions
    @State private var expanded = IntroStart.expanded
    @State private var toast: String?

    var body: some View {
        ScrollView {
            if let detail = model.detail {
                LazyVStack(alignment: .leading, spacing: 0) {
                    UploaderRow(owner: detail.owner, card: model.uploader, staff: detail.staff,
                                following: following ?? model.uploader?.following ?? false, onFollow: onFollow)
                        .padding(.top, 13)
                    TitleBlock(detail: detail, online: model.online, tags: model.tags, expanded: $expanded) { run in
                        Task { await model.activate(run) }
                    }
                    .padding(.top, 18)
                    actions()
                    if detail.pages.count > 1 {
                        PartStrip(detail: detail, current: model.current, onChoose: { play($0, of: detail) },
                                  onOpenList: { state.sheet = .parts })
                            .padding(.top, 16)
                    } else if let season = detail.season {
                        CollectionRow(season: season, current: model.current) { state.sheet = .collection }
                            .padding(.top, 16)
                    }
                    let chips = model.tags.filter { $0.kind != .normal }
                    if !chips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(chips, id: \.id) { TagChip(tag: $0) }
                            }
                            .padding(.horizontal, Theme.Metrics.gutter)
                        }
                        .padding(.top, 16)
                    }
                    RelatedList(cards: model.related, onOpen: { model.openRelated($0) }, onWatchLater: watchLater)
                        .padding(.top, 18)
                }
                .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .collapsingPlayerScroll(state, tab: .intro)
        .toast($toast)
    }

    private func play(_ page: VideoPage, of detail: VideoDetail) {
        Task { await model.play(PlayItem(bvid: detail.bvid, cid: page.cid), at: nil) }
    }

    private func watchLater(_ card: VideoCard) {
        Task {
            switch await model.addToWatchLater(aid: card.aid) {
            case .added: toast = "已添加至稍后再看"
            case .needsLogin: onNeedLogin()
            case .failed(let message): toast = message
            }
        }
    }
}

private enum IntroStart {
    static var expanded: Bool {
        #if DEBUG
        IntroDemo.expandsTitle
        #else
        false
        #endif
    }
}
