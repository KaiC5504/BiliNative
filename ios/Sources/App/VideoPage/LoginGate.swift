import SwiftUI
import UIKit

/// Full screen is the same page rotated, so a sheet goes up only after the page is back inline; a sheet over the
/// rotated player would be a system controller holding a view it may move.
@MainActor
enum InlineFirst {
    static func present(_ show: @escaping @MainActor () -> Void) {
        let orientation = OrientationController.shared
        let rotates = orientation.presentation != .inline
        if rotates { orientation.exitToInline() }
        Task {
            if rotates { await rotationFinished() }
            show()
        }
    }

    /// Waits for the scene to report portrait and for the rotation's animation to end. The limit only matters if
    /// the scene never turns back; the sheet then goes up anyway.
    private static func rotationFinished(limit: Duration = .seconds(3)) async {
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        while scene.effectiveGeometry.interfaceOrientation != .portrait, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        for window in scene.windows {
            guard let coordinator = window.rootViewController?.transitionCoordinator else { continue }
            // UIKit can accept the completion and never call it, so a timer resumes too.
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let once = Once()
                let queued = coordinator.animate(alongsideTransition: nil) { _ in if once.claim() { done.resume() } }
                if !queued, once.claim() { done.resume() }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if once.claim() { done.resume() }
                }
            }
        }
    }
}

/// Presents `LoginView` as a sheet when `requested` turns true, then resets it.
struct LoginGate: ViewModifier {
    @Binding var requested: Bool
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showing) { LoginView() }
            .onChange(of: requested) { _, asked in
                guard asked else { return }
                requested = false
                guard !showing else { return }
                InlineFirst.present { showing = true }
            }
    }
}

extension View {
    func loginGate(_ requested: Binding<Bool>) -> some View {
        modifier(LoginGate(requested: requested))
    }
}
