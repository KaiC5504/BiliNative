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
        if presentation != .inline { exitToInline() }
    }

    func enterLandscape() { move(to: .landscape) }

    func enterVertical() { move(to: .vertical) }

    func exitToInline() { move(to: .inline) }

    func deviceOrientationChanged(_ orientation: UIDeviceOrientation) {
        guard !locked, !videoIsVertical else { return }
        switch presentation {
        case .inline where orientation.isLandscape:
            enterLandscape()
        case .landscape where orientation == .portrait:
            exitToInline()
        default:
            break
        }
    }

    /// Asks the scene again even when the presentation is unchanged, so a refused rotation can be retried.
    private func move(to next: Presentation) {
        if next != presentation {
            Logger.shared.info(.ui, "presentation", ["from": .init(String(describing: presentation)), "to": .init(String(describing: next))])
            presentation = next
        }
        applyMask()
    }

    private func applyMask() {
        guard let scene = Self.scene else { return }
        for window in scene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(preferences) { error in
            Logger.shared.warn(.ui, "orientation request refused", ["error": .init(String(describing: error))])
        }
    }

    private static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
