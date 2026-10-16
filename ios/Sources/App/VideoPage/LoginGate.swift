import SwiftUI

/// Full screen is the same page rotated, so a sheet goes up only after the page is back inline; a sheet over the
/// rotated player would be a system controller holding a view it may move.
@MainActor
enum InlineFirst {
    static func present(_ show: @escaping @MainActor () -> Void) {
        let orientation = OrientationController.shared
        let rotates = orientation.presentation != .inline
        if rotates { orientation.exitToInline() }
        Task {
            if rotates { try? await Task.sleep(for: .milliseconds(450)) }
            show()
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
