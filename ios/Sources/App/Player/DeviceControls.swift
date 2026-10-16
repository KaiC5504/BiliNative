import AVFoundation
import MediaPlayer
import UIKit
import DevLog

@MainActor
enum DeviceControls {
    static var brightness: Double {
        get { Double(screen?.brightness ?? 0.5) }
        set { screen?.brightness = CGFloat(min(max(newValue, 0), 1)) }
    }

    /// The brightness from before full screen, put back when the player returns inline, as the official app does.
    private static var savedBrightness: CGFloat?

    static func saveBrightness() {
        guard savedBrightness == nil, let screen else { return }
        savedBrightness = screen.brightness
    }

    static func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        savedBrightness = nil
        screen?.brightness = saved
    }

    static func volume() -> Double {
        Double(AVAudioSession.sharedInstance().outputVolume)
    }

    /// A hidden MPVolumeView's slider is the only public way to set the system volume. While that view sits in
    /// the window iOS also leaves out its own volume HUD, so it is there only in full screen, where the player's
    /// indicator takes the HUD's place; inline the buttons show the system HUD as usual.
    static func attachVolumeView() {
        _ = attachedSlider()
        observeVolume()
    }

    static func detachVolumeView() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
    }

    /// Posted for a volume change made with the hardware buttons while the volume view hides the system HUD.
    /// `userInfo["volume"]` holds the new level.
    static let hardwareVolumeChanged = Notification.Name("DeviceControls.hardwareVolumeChanged")

    static func setVolume(_ value: Double) {
        let level = Float(min(max(value, 0), 1))
        lastOwnVolumeChange = Date()
        let (slider, fresh) = attachedSlider()
        guard let slider else {
            if !reportedMissingSlider {
                reportedMissingSlider = true
                Logger.shared.warn(.ui, "volume slider not found; the volume gesture does nothing")
            }
            return
        }
        // A slider that has only just joined the window ignores a value set in the same run loop turn.
        if fresh {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                lastOwnVolumeChange = Date()
                slider.value = level
            }
        } else {
            slider.value = level
        }
    }

    private static var volumeView: MPVolumeView?
    private static var reportedMissingSlider = false
    private static var volumeObservation: NSKeyValueObservation?
    private static var lastOwnVolumeChange: Date?

    private static func observeVolume() {
        guard volumeObservation == nil else { return }
        // KVO calls back on an audio thread, so the handler must not be main-actor isolated.
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { @Sendable _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in DeviceControls.volumeChanged(Double(value)) }
        }
    }

    private static func volumeChanged(_ value: Double) {
        guard volumeObservation != nil else { return }
        // The system reports our own slider moves too, a little after the drag set them.
        if let last = lastOwnVolumeChange, Date().timeIntervalSince(last) < 0.5 { return }
        NotificationCenter.default.post(name: hardwareVolumeChanged, object: nil, userInfo: ["volume": value])
    }

    private static func attachedSlider() -> (UISlider?, fresh: Bool) {
        if let volumeView, volumeView.window != nil {
            return (slider(in: volumeView), false)
        }
        guard let window = keyWindow else { return (nil, false) }
        volumeView?.removeFromSuperview()
        // Inside the window's bounds: a view placed off screen may no longer keep the system HUD away.
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        window.addSubview(view)
        volumeView = view
        return (slider(in: view), true)
    }

    private static func slider(in view: UIView) -> UISlider? {
        for subview in view.subviews {
            if let slider = subview as? UISlider { return slider }
            if let slider = slider(in: subview) { return slider }
        }
        return nil
    }

    private static var screen: UIScreen? {
        keyWindow?.windowScene?.screen
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}
