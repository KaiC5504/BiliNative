import AVFoundation
import QuartzCore
import UIKit
import Danmaku

/// Draws danmaku over the video. A display link reads the player's own clock every frame, so pausing, the
/// playback rate, stalls and seeks carry over without any events.
final class DanmakuView: UIView {
    private struct Item {
        let layer: CALayer
        let kind: LaneLayout.Kind
        let reverse: Bool
        /// Video time, in seconds, at which it entered.
        let start: Double
        let width: CGFloat
        let y: CGFloat
    }

    /// What the lanes are laid out for; a change clears the screen and lays it out again.
    private struct Geometry: Equatable {
        var size: CGSize
        var fullScreen: Bool
        var area: Double
        var scale: Double
        var speed: Int
    }

    private static let staticDuration = 4.0

    private let controller: DanmakuController
    private let settings: AppSettings
    private let player: @MainActor () -> AVPlayer?
    private let fullScreen: @MainActor () -> Bool
    private var link: CADisplayLink?
    private var layout = LaneLayout(lanes: 0, width: 0, scrollDuration: 7)
    private var geometry: Geometry?
    private var lanes = 0
    private var laneHeight: CGFloat = 0
    private var basePointSize: CGFloat = 17
    private var scrollDuration = 7.0
    private var items: [Item] = []
    private var spare: [CALayer] = []
    private var lastTime: Double?
    private var generation = -1
    private var fonts: [CGFloat: UIFont] = [:]
    private let images = NSCache<NSString, UIImage>()

    init(controller: DanmakuController, settings: AppSettings, player: @escaping @MainActor () -> AVPlayer?,
         fullScreen: @escaping @MainActor () -> Bool = { OrientationController.shared.presentation != .inline }) {
        self.controller = controller
        self.settings = settings
        self.player = player
        self.fullScreen = fullScreen
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        images.countLimit = 400
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Live danmaku and where they are (tests).
    var visibleFrames: [(kind: LaneLayout.Kind, frame: CGRect)] { items.map { (kind: $0.kind, frame: $0.layer.frame) } }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            link?.invalidate()
            link = nil
            clear()
            lastTime = nil
        } else if link == nil {
            let link = CADisplayLink(target: LinkTarget(self), selector: #selector(LinkTarget.step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    fileprivate func step() {
        let options = settings.danmaku
        guard options.enabled, !controller.closed, let player = player(), player.currentItem != nil else {
            if !items.isEmpty { clear() }
            lastTime = nil
            return
        }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        show(at: max(seconds, 0), playing: player.rate != 0, options: options)
    }

    /// One frame at video time `time`; the display link calls it, tests call it directly.
    func show(at seconds: Double, playing: Bool, options: DanmakuSettings) {
        var time = seconds
        var relay = lastTime == nil
        let next = Geometry(size: bounds.size, fullScreen: fullScreen(), area: options.area, scale: options.scale, speed: options.speed)
        if next != geometry {
            configure(next, scrollDuration: options.scrollDuration)
            relay = true
        }
        if let last = lastTime {
            if time < last {
                // The player's clock can step back by a hair; only a real jump is a seek.
                if last - time < 0.2 { time = last } else { relay = true }
            } else if time - last > 0.9 {
                // Under the timeline's 1 s jump limit, so a jump is always re-laid rather than skipped.
                relay = true
            }
        }
        let ms = Int64(time * 1000)
        controller.update(positionMs: ms, playing: playing)
        if controller.generation != generation {
            generation = controller.generation
            relay = true
        }
        if relay {
            clear()
            controller.seeked(toMs: ms)
        }
        let fresh = controller.pendingItems(atMs: ms)
        let opacity = CGFloat(options.opacity)
        if alpha != opacity { alpha = opacity }
        guard relay || !fresh.isEmpty || time != lastTime else { return }
        lastTime = time
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for danmaku in fresh { place(danmaku, at: time) }
        move(to: time)
        CATransaction.commit()
    }

    private func configure(_ next: Geometry, scrollDuration: Double) {
        geometry = next
        self.scrollDuration = scrollDuration
        basePointSize = CGFloat(next.scale) * (next.fullScreen ? 22 : 17)
        let lineHeight = font(ofSize: basePointSize).lineHeight
        // Tiny fonts: the outline and own box padding must still fit, or neighbouring lanes would touch.
        laneHeight = max(lineHeight * 1.2, ceil(lineHeight) + 3)
        lanes = laneHeight > 0 ? max(Int((next.size.height * CGFloat(next.area) / laneHeight).rounded(.down)), 0) : 0
    }

    private func place(_ danmaku: DisplayDanmaku, at time: Double) {
        let start = Double(danmaku.elem.progressMs) / 1000
        let kind: LaneLayout.Kind
        switch danmaku.elem.mode {
        case 4: kind = .bottom
        case 5: kind = .top
        default: kind = .scroll
        }
        // Re-laid after a seek: one that would already have left is not drawn at all.
        guard time - start < (kind == .scroll ? scrollDuration : Self.staticDuration) else { return }
        let image = image(for: danmaku)
        guard let lane = layout.place(kind, width: Double(image.size.width), at: start) else { return }
        let top = kind == .bottom ? bounds.height - CGFloat(lanes - lane) * laneHeight : CGFloat(lane) * laneHeight
        let y = top + laneHeight / 2
        let layer = spare.popLast() ?? makeLayer()
        layer.contents = image.cgImage
        layer.contentsScale = image.scale
        layer.bounds = CGRect(origin: .zero, size: image.size)
        layer.position = CGPoint(x: bounds.width / 2, y: y)
        layer.isHidden = false
        items.append(Item(layer: layer, kind: kind, reverse: danmaku.elem.mode == 6, start: start, width: image.size.width, y: y))
    }

    /// x = W - (t - start) × (W + w) / D for a scrolling danmaku, mirrored for reverse ones.
    private func move(to time: Double) {
        let width = bounds.width
        var index = 0
        while index < items.count {
            let item = items[index]
            let age = time - item.start
            let lifetime = item.kind == .scroll ? scrollDuration : Self.staticDuration
            // At exactly its lifetime a static danmaku's lane is already handed to the next one.
            if age < 0 || age >= lifetime {
                recycle(item.layer)
                items.swapAt(index, items.count - 1)
                items.removeLast()
                continue
            }
            if item.kind == .scroll {
                let travelled = CGFloat(age / scrollDuration) * (width + item.width)
                let left = item.reverse ? travelled - item.width : width - travelled
                item.layer.position = CGPoint(x: left + item.width / 2, y: item.y)
            }
            index += 1
        }
    }

    private func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items { recycle(item.layer) }
        CATransaction.commit()
        items.removeAll(keepingCapacity: true)
        layout.reset(lanes: lanes, width: Double(bounds.width), scrollDuration: scrollDuration)
    }

    private func makeLayer() -> CALayer {
        let made = CALayer()
        layer.addSublayer(made)
        return made
    }

    private func recycle(_ item: CALayer) {
        item.isHidden = true
        item.contents = nil
        spare.append(item)
    }

    private func font(ofSize size: CGFloat) -> UIFont {
        if let cached = fonts[size] { return cached }
        let made = UIFont.systemFont(ofSize: size, weight: .semibold)
        fonts[size] = made
        return made
    }

    private func image(for danmaku: DisplayDanmaku) -> UIImage {
        let fontSize = danmaku.elem.fontSize > 0 ? danmaku.elem.fontSize : 25
        let pointSize = basePointSize * CGFloat(fontSize) / 25
        let color = danmaku.elem.color & 0xFFFFFF
        let key = "\(pointSize)|\(color)|\(danmaku.isOwn)|\(danmaku.text)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let made = Self.render(danmaku.text, font: font(ofSize: pointSize), color: color, own: danmaku.isOwn)
        images.setObject(made, forKey: key)
        return made
    }

    /// The text with a 1 pt dark outline; one's own danmaku also get a white rounded box.
    static func render(_ text: String, font: UIFont, color rgb: UInt32, own: Bool) -> UIImage {
        let line = (text.contains("\n") || text.contains("\r")) ? text.components(separatedBy: .newlines).joined(separator: " ") : text
        let string = line as NSString
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        let fill = UIColor(red: red, green: green, blue: blue, alpha: 1)
        // Very dark text would vanish inside a dark outline, so it gets a light one.
        let dark = 0.299 * red + 0.587 * green + 0.114 * blue < 0.25
        let outline = dark ? UIColor(white: 1, alpha: 0.85) : UIColor(white: 0, alpha: 0.85)
        let textSize = string.size(withAttributes: [.font: font])
        let padX: CGFloat = own ? 5 : 1
        let padY: CGFloat = own ? 1.5 : 1
        let size = CGSize(width: ceil(textSize.width) + padX * 2, height: ceil(font.lineHeight) + padY * 2)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let origin = CGPoint(x: padX, y: padY)
            // A positive stroke width draws the outline only, as a percentage of the point size; the fill on
            // top hides its inner half, leaving 1 pt outside the glyphs.
            string.draw(at: origin, withAttributes: [.font: font, .strokeColor: outline, .strokeWidth: 200 / font.pointSize])
            string.draw(at: origin, withAttributes: [.font: font, .foregroundColor: fill])
            if own {
                let box = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
                box.lineWidth = 1
                UIColor.white.setStroke()
                box.stroke()
            }
        }
    }
}

/// CADisplayLink retains its target; this one holds the view weakly so the view can go away.
@MainActor
private final class LinkTarget: NSObject {
    weak var view: DanmakuView?

    init(_ view: DanmakuView) {
        self.view = view
    }

    @objc func step(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.step()
    }
}

/// Keeps one renderer per page across SwiftUI updates.
@MainActor
final class DanmakuSlot {
    private var made: DanmakuView?

    func view(for model: VideoPageModel, settings: AppSettings) -> DanmakuView {
        if let made { return made }
        let view = DanmakuView(controller: model.danmaku, settings: settings, player: { [weak model] in model?.controller?.player })
        made = view
        return view
    }
}
