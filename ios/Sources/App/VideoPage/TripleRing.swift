import SwiftUI

/// 长按三连: the ring waits a moment so a tap stays a tap, then fills.
enum TripleTiming {
    static let delay = 0.2
    static let fill = 1.2
}

/// A pink ring that fills around an action's icon while 点赞 is held, and a burst when 三连 fires.
struct TripleRing: View {
    let progress: Double
    let burst: Int

    private enum Phase: CaseIterable {
        case rest, flash, spread
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.pink, style: StrokeStyle(lineWidth: Theme.Actions.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
            burstView
        }
        .frame(width: Theme.Actions.ring, height: Theme.Actions.ring)
        .allowsHitTesting(false)
    }

    private var burstView: some View {
        ZStack {
            Circle()
                .stroke(Theme.pink, lineWidth: Theme.Actions.ringWidth)
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(Theme.pink)
                    .frame(width: 4, height: 4)
                    .offset(y: -Theme.Actions.ring / 2)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .phaseAnimator(Phase.allCases, trigger: burst) { content, phase in
            content
                .scaleEffect(phase == .spread ? 1.6 : 1)
                .opacity(phase == .flash ? 1 : 0)
        } animation: { phase in
            phase == .spread ? .easeOut(duration: 0.5) : nil
        }
    }
}

extension View {
    /// The ring sits on the icon, which is the top of the cell.
    func tripleRing(progress: Double, burst: Int) -> some View {
        overlay(alignment: .top) {
            TripleRing(progress: progress, burst: burst)
                .offset(y: (Theme.Actions.iconSize - Theme.Actions.ring) / 2)
        }
    }
}
