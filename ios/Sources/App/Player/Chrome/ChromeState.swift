import CoreGraphics
import Observation
import AppLogic

enum HUD: Equatable {
    case speedUp
    case seek(label: String)
    case level(Level, Double)

    enum Level { case brightness, volume }
}

/// Whether the player's controls show, what the HUD says, and what each gesture on the video does.
@MainActor
@Observable
final class ChromeState {
    var visible = true
    var hud: HUD?
    /// Where a seek drag or the progress bar is aiming; the bar shows it instead of the playhead.
    var scrubbing: Double? {
        didSet { if scrubbing == nil, oldValue != nil, visible { scheduleHide() } }
    }
    /// The page sets this while a picker or panel is open, so the controls under it stay put.
    var panelOpen = false {
        didSet { if !panelOpen, oldValue, visible { scheduleHide() } }
    }
    /// Off on demo screens, which are photographed with the controls showing.
    var autoHides = true

    @ObservationIgnored private let sleep: (Double) async -> Void
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var seekStart: Double?
    @ObservationIgnored private var seekCount = 0
    @ObservationIgnored private var levelStart: Double?
    @ObservationIgnored private var holding = false
    @ObservationIgnored private var volumeHUDTask: Task<Void, Never>?

    init(sleep: @escaping (Double) async -> Void = { seconds in
        _ = try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }) {
        self.sleep = sleep
    }

    /// Shows the controls and restarts the hide timer.
    func touch() {
        visible = true
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        visible = false
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard autoHides else {
            hideTask = nil
            return
        }
        let sleep = self.sleep
        hideTask = Task { [weak self] in
            await sleep(Theme.Chrome.hideDelay)
            guard !Task.isCancelled, let self, self.scrubbing == nil, !self.panelOpen else { return }
            self.visible = false
        }
    }

    func handle(_ event: PlayerGestureEvent, page: VideoPageModel, size: CGSize) {
        switch event {
        case .tap:
            if visible { hide() } else { touch() }
        case .doubleTap:
            page.togglePlay()
            touch()
        case .holdBegan:
            // The page's rate stays what the 倍速 picker chose, so release and a part switch both restore it.
            guard let controller = page.controller, controller.isPlaying else { return }
            holding = true
            controller.rate = 2
            hud = .speedUp
            hide()
        case .holdEnded:
            guard holding else { return }
            holding = false
            page.controller?.rate = page.rate
            if hud == .speedUp { hud = nil }
        case .seekChanged(let dx):
            guard let controller = page.controller else { return }
            let start = seekStart ?? controller.position
            seekStart = start
            let duration = controller.duration
            let target = GestureMath.seekTarget(start: start, dx: dx, width: Double(size.width), duration: duration)
            seekCount += 1
            scrubbing = target
            hud = .seek(label: TimeFormat.pair(target, duration))
        case .seekEnded(let dx):
            guard let controller = page.controller else {
                seekStart = nil
                scrubbing = nil
                hud = nil
                return
            }
            let start = seekStart ?? controller.position
            seekStart = nil
            let target = GestureMath.seekTarget(start: start, dx: dx, width: Double(size.width), duration: controller.duration)
            if case .seek? = hud { hud = nil }
            commit(target, page: page)
        case .levelChanged(let side, let dy):
            let level: HUD.Level = side == .left ? .brightness : .volume
            let start = levelStart ?? (level == .brightness ? DeviceControls.brightness : DeviceControls.volume())
            levelStart = start
            let value = GestureMath.level(start: start, dy: dy, height: Double(size.height))
            if level == .brightness {
                DeviceControls.brightness = value
            } else {
                DeviceControls.setVolume(value)
            }
            hud = .level(level, value)
        case .levelEnded:
            levelStart = nil
            if case .level? = hud { hud = nil }
        }
    }

    /// The hardware volume buttons in full screen, where iOS leaves out its own HUD: shows the level for a second.
    func showHardwareVolume(_ value: Double) {
        guard levelStart == nil else { return }
        hud = .level(.volume, value)
        volumeHUDTask?.cancel()
        let sleep = self.sleep
        volumeHUDTask = Task { [weak self] in
            await sleep(1)
            guard !Task.isCancelled, let self, self.levelStart == nil, case .level(.volume, _)? = self.hud else { return }
            self.hud = nil
        }
    }

    /// The progress bar's drag: shows the target until the finger lifts.
    func scrub(to seconds: Double) {
        seekCount += 1
        scrubbing = seconds
        hideTask?.cancel()
    }

    /// Seeks, and keeps showing the target until the seek lands so the bar does not jump back.
    func commit(_ seconds: Double, page: VideoPageModel) {
        seekCount += 1
        let count = seekCount
        scrubbing = seconds
        Task { [weak self] in
            await page.seek(to: seconds)
            guard let self, self.seekCount == count else { return }
            self.scrubbing = nil
        }
    }
}
