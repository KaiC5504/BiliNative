import Observation
import UIKit
import DevLog

/// Full screen is the same page rotated, never a presented controller: the app delegate's orientation mask
/// follows `presentation`, and the scene is asked to rotate to it.
@MainActor
@Observable
final class OrientationController {
    enum Presentation: Equatable { case inline, landscape, vertical }

    static let shared = OrientationController()

    private(set) var presentation: Presentation = .inline
    /// The rotation lock: turning the phone does nothing until it is lifted, and it lasts until the page closes.
    var locked = false
    var videoIsVertical = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// Landscape was entered by the button with the phone flat or upright. Lifting it off the table reports
    /// portrait before anyone has turned it, so portrait only exits once the phone has really been landscape.
    @ObservationIgnored private var awaitingLandscape = false
    /// Bumped by every request, so a late refusal cannot undo a newer move.
    @ObservationIgnored private var requests = 0
    /// Tests replace it to simulate a refused rotation.
    @ObservationIgnored var requestGeometry: @MainActor (UIWindowScene, UIWindowScene.GeometryPreferences,
                                                         @escaping @Sendable (any Error) -> Void) -> Void = { scene, preferences, refused in
        scene.requestGeometryUpdate(preferences, errorHandler: refused)
    }

    private init() {}

    var mask: UIInterfaceOrientationMask {
        switch presentation {
        case .inline, .vertical:
            return .portrait
        case .landscape:
            // Locked in landscape keeps the side it is on rather than flipping with the phone.
            guard locked, let current = Self.scene?.effectiveGeometry.interfaceOrientation else { return .landscape }
            switch current {
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: return .landscape
            }
        }
    }

    func begin() {
        guard observer == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deviceOrientationChanged(UIDevice.current.orientation)
            }
        }
    }

    func end() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            self.observer = nil
        }
        locked = false
        videoIsVertical = false
        if presentation != .inline { exitToInline() }
        DeviceControls.detachVolumeView()
        DeviceControls.restoreBrightness()
    }

    func enterLandscape() {
        awaitingLandscape = !UIDevice.current.orientation.isLandscape
        move(to: .landscape)
    }

    func enterVertical() { move(to: .vertical) }

    func exitToInline() { move(to: .inline) }

    func deviceOrientationChanged(_ orientation: UIDeviceOrientation) {
        if orientation.isLandscape { awaitingLandscape = false }
        guard !locked, !videoIsVertical else { return }
        switch presentation {
        case .inline where orientation.isLandscape:
            move(to: .landscape)
        case .landscape where orientation == .portrait && !awaitingLandscape:
            exitToInline()
        default:
            break
        }
    }

    /// Asks the scene again even when the presentation is unchanged, so a refused rotation can be retried.
    private func move(to next: Presentation) {
        let previous = presentation
        if next != presentation {
            Logger.shared.info(.ui, "presentation", ["from": .init(String(describing: presentation)), "to": .init(String(describing: next))])
            presentation = next
        }
        if next == .inline { awaitingLandscape = false }
        fullScreenChanged()
        requests += 1
        let request = requests
        applyMask { [self] in
            // Going back inline is never undone: the page may be closing, and portrait is the safe state.
            guard request == requests, presentation == next, next != .inline, previous != next else { return }
            Logger.shared.info(.ui, "presentation", ["from": .init(String(describing: next)), "to": .init(String(describing: previous)),
                                                     "reason": .init("rotation refused")])
            presentation = previous
            if previous == .inline { awaitingLandscape = false }
            fullScreenChanged()
            updateSupportedOrientations()
        }
    }

    private func fullScreenChanged() {
        if presentation == .inline {
            DeviceControls.detachVolumeView()
            DeviceControls.restoreBrightness()
        } else {
            DeviceControls.saveBrightness()
            DeviceControls.attachVolumeView()
        }
    }

    private func applyMask(refused: @escaping @MainActor @Sendable () -> Void) {
        guard let scene = Self.scene else { return }
        updateSupportedOrientations()
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        requestGeometry(scene, preferences) { error in
            Logger.shared.warn(.ui, "orientation request refused", ["error": .init(String(describing: error))])
            Task { @MainActor in refused() }
        }
    }

    private func updateSupportedOrientations() {
        guard let scene = Self.scene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
