import SwiftUI
import AppLogic

/// The small player's controls (15): back and ⋮ at the top; play, the bar, the time, 竖屏 and full screen at the
/// bottom. While they are hidden a thin progress line runs along the bottom edge.
struct PortraitControls: View {
    let model: VideoPageModel
    let chrome: ChromeState
    @Binding var panel: PlayerPanel?
    let onBack: () -> Void

    var body: some View {
        let controller = model.controller
        let duration = controller?.duration ?? 0
        let position = chrome.scrubbing ?? controller?.position ?? 0
        ZStack {
            if chrome.visible {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Theme.Chrome.shade, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, Theme.Chrome.shade], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ChromeButton(systemName: "chevron.left", label: "返回", action: onBack)
                        Spacer(minLength: 0)
                        MoreButton { open(.more) }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        PlayButton(model: model, font: Theme.Chrome.playFont) { chrome.touch() }
                        ProgressBar(position: position, duration: duration, buffered: controller?.buffered ?? 0,
                                    chapters: model.chapters,
                                    onScrub: { chrome.scrub(to: $0) },
                                    onCommit: { chrome.commit($0, page: model) })
                            .padding(.leading, 1)
                        Text(TimeFormat.pair(position, duration))
                            .font(Theme.Chrome.timeFont)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.leading, 9)
                            .padding(.trailing, 10)
                        Button {
                            chrome.touch()
                            OrientationController.shared.enterVertical()
                        } label: {
                            BadgedGlyph(badge: "竖屏", offset: CGSize(width: 12, height: -16)) {
                                CornersGlyph(inward: false)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                                    .frame(width: 14.5, height: 17)
                            }
                        }
                        .accessibilityLabel("竖屏")
                        Button {
                            chrome.touch()
                            enterFullScreen()
                        } label: {
                            FullScreenGlyph()
                                .stroke(.white, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                                .frame(width: 15.5, height: 15.5)
                                .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("全屏")
                        .padding(.leading, 2)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 1)
                .transition(.opacity)
            } else if !model.ended {
                HiddenProgressLine(position: position, duration: duration)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: chrome.visible)
    }

    private func open(_ next: PlayerPanel) {
        panel = next
    }

    private func enterFullScreen() {
        if model.detail?.isVertical == true {
            OrientationController.shared.enterVertical()
        } else {
            OrientationController.shared.enterLandscape()
        }
    }
}

// MARK: shared pieces of the three layouts

struct ChromeButton: View {
    let systemName: String
    let label: String
    var font: Font = .system(size: 19, weight: .medium)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(.white)
                .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3.2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white).frame(width: 4.4, height: 4.4)
                }
            }
            .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更多")
    }
}

struct PlayButton: View {
    let model: VideoPageModel
    let font: Font
    let onTap: () -> Void

    var body: some View {
        let playing = model.controller?.isPlaying == true && !model.ended
        Button {
            model.togglePlay()
            onTap()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(font)
                .foregroundStyle(.white)
                .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "暂停" : "播放")
    }
}

/// An icon with a small outlined pill above it to the right, like the 竖屏 and 详情页 buttons.
struct BadgedGlyph<Glyph: View>: View {
    let badge: String
    let offset: CGSize
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        glyph()
            .frame(width: Theme.Chrome.button, height: Theme.Chrome.button)
            .overlay {
                Text(badge)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
                    .padding(.horizontal, 4)
                    .frame(height: 11.5)
                    .background(Color.black.opacity(0.25), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                    .offset(offset)
            }
            .contentShape(Rectangle())
    }
}

/// Four corner brackets: pointing out (the 竖屏 button) or in (详情页, back to the page).
struct CornersGlyph: Shape {
    var inward: Bool

    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.3
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, sx, sy) in corners {
            if inward {
                // The bracket's elbow sits in from the corner, its arms pointing back towards the edges.
                let elbow = CGPoint(x: corner.x + sx * arm, y: corner.y + sy * arm)
                path.move(to: CGPoint(x: corner.x, y: elbow.y))
                path.addLine(to: elbow)
                path.addLine(to: CGPoint(x: elbow.x, y: corner.y))
            } else {
                path.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
            }
        }
        return path
    }
}

/// The full-screen button: a top-left and a bottom-right bracket.
struct FullScreenGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = rect.width * 0.56
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        return path
    }
}
