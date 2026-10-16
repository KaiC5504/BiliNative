import SwiftUI

/// What a gesture is doing (25): the 倍速中 pill at the top centre, the seek target, or brightness and volume.
struct PlayerHUD: View {
    let hud: HUD?

    var body: some View {
        ZStack {
            switch hud {
            case .speedUp?:
                HStack(spacing: 7) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15))
                    Text("倍速中")
                        .font(Theme.Chrome.hudFont)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.Chrome.hudFill, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .seek(let label)?:
                Text(label)
                    .font(Theme.Chrome.hudFont.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.Chrome.hudFill, in: RoundedRectangle(cornerRadius: 8))
            case .level(let kind, let value)?:
                HStack(spacing: 10) {
                    Image(systemName: symbol(kind, value))
                        .font(.system(size: 16))
                        .frame(width: 22)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Chrome.track)
                        Capsule().fill(.white).frame(width: 100 * CGFloat(min(max(value, 0), 1)))
                    }
                    .frame(width: 100, height: Theme.Chrome.barHeight)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Theme.Chrome.hudFill, in: RoundedRectangle(cornerRadius: 8))
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: hud)
    }

    private func symbol(_ kind: HUD.Level, _ value: Double) -> String {
        switch kind {
        case .brightness: return "sun.max.fill"
        case .volume: return value <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
    }
}
