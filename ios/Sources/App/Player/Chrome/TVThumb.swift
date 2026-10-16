import SwiftUI

/// The progress bar's thumb: our own small TV face, a white screen with two eyes in a dark rounded body with
/// two antennae. Drawn in a `Theme.Chrome.thumbSize` box.
struct TVThumb: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let unit = w / 18
            let bodyRect = CGRect(x: 1 * unit, y: 3.2 * unit, width: 16 * unit, height: h - 4.2 * unit)
            let rim = bodyRect.insetBy(dx: -0.9 * unit, dy: -0.9 * unit)
            context.fill(Path(roundedRect: rim, cornerRadius: 4.6 * unit), with: .color(Theme.Chrome.thumbRim))

            var antennae = Path()
            antennae.move(to: CGPoint(x: 6.2 * unit, y: bodyRect.minY + 0.6 * unit))
            antennae.addLine(to: CGPoint(x: 4.2 * unit, y: 0.9 * unit))
            antennae.move(to: CGPoint(x: 11.8 * unit, y: bodyRect.minY + 0.6 * unit))
            antennae.addLine(to: CGPoint(x: 13.8 * unit, y: 0.9 * unit))
            context.stroke(antennae, with: .color(.black), style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round))

            context.fill(Path(roundedRect: bodyRect, cornerRadius: 3.8 * unit), with: .color(.black))
            let screen = bodyRect.insetBy(dx: 1.7 * unit, dy: 1.5 * unit)
            context.fill(Path(roundedRect: screen, cornerRadius: 2.2 * unit), with: .color(.white))

            let eye = CGSize(width: 1.7 * unit, height: min(4.2 * unit, screen.height * 0.5))
            for dx in [-2.7 * unit, 2.7 * unit] {
                let rect = CGRect(x: screen.midX + dx - eye.width / 2, y: screen.midY - eye.height / 2,
                                  width: eye.width, height: eye.height)
                context.fill(Path(roundedRect: rect, cornerRadius: eye.width / 2), with: .color(.black))
            }
        }
        .frame(width: Theme.Chrome.thumbSize.width, height: Theme.Chrome.thumbSize.height)
        .accessibilityHidden(true)
    }
}
