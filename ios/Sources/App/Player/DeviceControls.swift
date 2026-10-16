import AVFoundation
import MediaPlayer
import UIKit
import DevLog

@MainActor
enum DeviceControls {
    static var brightness: Double {
        get { Double(keyWindow?.windowScene?.screen.brightness ?? 0.5) }
        set { keyWindow?.windowScene?.screen.brightness = CGFloat(min(max(newValue, 0), 1)) }
    }

    static func volume() -> Double {
        Double(AVAudioSession.sharedInstance().outputVolume)
    }

    /// A hidden MPVolumeView's slider is the only public way to set the system volume. While that view sits in
    /// the window, iOS also leaves out its own volume HUD, so the player's indicator is the only one shown.
    static func setVolume(_ value: Double) {
        let level = Float(min(max(value, 0), 1))
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
                slider.value = level
            }
        } else {
            slider.value = level
        }
    }

    private static var volumeView: MPVolumeView?
    private static var reportedMissingSlider = false

    private static func attachedSlider() -> (UISlider?, fresh: Bool) {
        if let volumeView, volumeView.window != nil {
            return (slider(in: volumeView), false)
        }
        guard let window = keyWindow else { return (nil, false) }
        volumeView?.removeFromSuperview()
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 120, height: 40))
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

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first
    }
}
