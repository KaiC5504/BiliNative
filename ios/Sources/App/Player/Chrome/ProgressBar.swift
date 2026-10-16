import SwiftUI
import BiliAPI

/// The seek bar: played in pink, buffered in white at 40%, the rest at 20%, a tick where each chapter starts,
/// and the TV-face thumb. While it is dragged, the chapter under the thumb shows its title above it.
struct ProgressBar: View {
    enum Style {
        /// The small player and landscape (15, 04).
        case tv
        /// 竖屏 full screen (09): white played part and a small dot.
        case dot
    }

    let position: Double
    let duration: Double
    let buffered: Double
    let chapters: [Chapter]
    var style: Style = .tv
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    @State private var dragging = false

    private var thumbWidth: CGFloat {
        style == .tv ? Theme.Chrome.thumbSize.width : Theme.Chrome.verticalDot
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = max(width - thumbWidth, 1)
            let played = fraction(position)
            let thumbX = travel * played
            ZStack(alignment: .leading) {
                track(width: width, travel: travel, playedTo: thumbX + thumbWidth / 2)
                thumb
                    .offset(x: thumbX)
            }
            .frame(width: width, height: geometry.size.height)
            .overlay(alignment: .topLeading) {
                if dragging, let title = chapterTitle {
                    Text(title)
                        .font(Theme.Chrome.smallFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Chrome.hudFill, in: RoundedRectangle(cornerRadius: 4))
                        .alignmentGuide(.leading) { label in
                            let centred = thumbX + thumbWidth / 2 - label.width / 2
                            return -min(max(centred, 0), max(width - label.width, 0))
                        }
                        .alignmentGuide(.top) { label in label.height + 6 }
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        onScrub(seconds(at: value.location.x, travel: travel))
                    }
                    .onEnded { value in
                        dragging = false
                        onCommit(seconds(at: value.location.x, travel: travel))
                    }
            )
        }
        .frame(height: Theme.Chrome.barTouchHeight)
        .accessibilityElement()
        .accessibilityLabel("进度")
        .accessibilityValue(Text(verbatim: "\(Int(position))/\(Int(duration))"))
    }

    @ViewBuilder
    private var thumb: some View {
        switch style {
        case .tv:
            TVThumb()
        case .dot:
            Circle()
                .fill(.white)
                .frame(width: Theme.Chrome.verticalDot, height: Theme.Chrome.verticalDot)
        }
    }

    private func track(width: CGFloat, travel: CGFloat, playedTo: CGFloat) -> some View {
        let height = Theme.Chrome.barHeight
        let bufferedTo = min(max(travel * fraction(buffered) + thumbWidth / 2, playedTo), width)
        return ZStack(alignment: .leading) {
            Capsule().fill(style == .tv ? Theme.Chrome.track : Theme.Chrome.verticalTrack)
            if style == .tv {
                Capsule().fill(Theme.Chrome.buffered).frame(width: bufferedTo)
            }
            Capsule().fill(style == .tv ? Theme.pink : Theme.Chrome.verticalPlayed).frame(width: max(playedTo, 0))
            ForEach(Array(chapterStarts.enumerated()), id: \.offset) { _, start in
                Rectangle()
                    .fill(Theme.Chrome.tick)
                    .frame(width: height, height: height)
                    .offset(x: travel * fraction(start) + thumbWidth / 2 - height / 2)
            }
        }
        .frame(width: width, height: height)
    }

    private var chapterStarts: [Double] {
        guard duration > 0 else { return [] }
        return chapters.map(\.from).filter { $0 > 0 && $0 < duration }
    }

    private var chapterTitle: String? {
        guard let title = chapters.last(where: { $0.from <= position })?.title, !title.isEmpty else { return nil }
        return title
    }

    private func fraction(_ seconds: Double) -> CGFloat {
        guard duration > 0, seconds.isFinite else { return 0 }
        return CGFloat(min(max(seconds / duration, 0), 1))
    }

    private func seconds(at x: CGFloat, travel: CGFloat) -> Double {
        let ratio = min(max((x - thumbWidth / 2) / travel, 0), 1)
        return Double(ratio) * max(duration, 0)
    }
}

/// The thin line along the small player's bottom edge while its controls are hidden.
struct HiddenProgressLine: View {
    let position: Double
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            let ratio: CGFloat = duration > 0 ? CGFloat(min(max(position / duration, 0), 1)) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.Chrome.track)
                Rectangle().fill(Theme.pink).frame(width: geometry.size.width * ratio)
            }
        }
        .frame(height: Theme.Chrome.hiddenLine)
        .allowsHitTesting(false)
    }
}
