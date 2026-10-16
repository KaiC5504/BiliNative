import SwiftUI

/// Presents `LoginView` as a sheet when `requested` turns true, then resets it. Full screen is the same page
/// rotated, so it goes back to inline before the sheet comes up rather than putting a sheet over the rotated player.
struct LoginGate: ViewModifier {
    @Binding var requested: Bool
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showing) { LoginView() }
            .onChange(of: requested) { _, asked in
                guard asked else { return }
                requested = false
                present()
            }
    }

    private func present() {
        guard !showing else { return }
        let orientation = OrientationController.shared
        let rotates = orientation.presentation != .inline
        if rotates { orientation.exitToInline() }
        Task {
            if rotates { try? await Task.sleep(for: .milliseconds(450)) }
            showing = true
        }
    }
}

extension View {
    func loginGate(_ requested: Binding<Bool>) -> some View {
        modifier(LoginGate(requested: requested))
    }
}
