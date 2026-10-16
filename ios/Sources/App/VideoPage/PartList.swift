import SwiftUI
import AppLogic
import BiliAPI

/// A multi-part video's parts: "选集 N/M >" over a strip of chips. The header opens the full list.
struct PartStrip: View {
    let detail: VideoDetail
    let current: PlayItem?
    let onChoose: (VideoPage) -> Void
    let onOpenList: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenList) {
                HStack(spacing: 0) {
                    Text("选集")
                        .font(Theme.Page.bodyFont)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(PartList.position(detail: detail, current: current))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.leading, 6)
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(detail.pages, id: \.cid) { page in
                            let selected = current?.cid == page.cid
                            Button {
                                if !selected { onChoose(page) }
                            } label: {
                                Text("P\(page.page) \(page.part)")
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                    .foregroundStyle(selected ? Theme.pink : Theme.text)
                                    .padding(.horizontal, 14)
                                    .frame(maxWidth: 160)
                                    .frame(height: 34)
                                    .background(selected ? Theme.pinkTint : Theme.softGrey,
                                                in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .id(page.cid)
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.gutter)
                }
                .onAppear {
                    if let cid = current?.cid { reader.scrollTo(cid, anchor: .center) }
                }
                .onChange(of: current?.cid) { _, cid in
                    guard let cid else { return }
                    withAnimation { reader.scrollTo(cid, anchor: .center) }
                }
            }
        }
    }
}

/// Every part of a multi-part video, the playing one pink.
struct PartList: View {
    let detail: VideoDetail
    let current: PlayItem?
    let onChoose: (VideoPage) -> Void
    let onClose: () -> Void

    /// "2/5", the playing part's number among the parts.
    static func position(detail: VideoDetail, current: PlayItem?) -> String {
        guard let index = detail.pages.firstIndex(where: { $0.cid == current?.cid }) else { return "\(detail.pages.count)" }
        return "\(index + 1)/\(detail.pages.count)"
    }

    var body: some View {
        PageSheetFrame(title: "选集 (\(detail.pages.count))", onClose: onClose) { dismiss in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(detail.pages, id: \.cid) { page in
                        let selected = current?.cid == page.cid
                        Button {
                            if !selected { onChoose(page) }
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                if selected {
                                    PlayingBars(color: Theme.pink)
                                        .frame(width: 11, height: 13)
                                }
                                Text("P\(page.page) \(page.part)")
                                    .font(.system(size: 14))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(TimeFormat.clock(Double(page.duration)))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .foregroundStyle(selected ? Theme.pink : Theme.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 46)
                            .background(selected ? Theme.pinkTint : Theme.softGrey,
                                        in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Theme.Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }
}
