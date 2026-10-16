import SwiftUI

struct Toast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(Theme.panelText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Theme.toastFill, in: Capsule())
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let message {
                        Toast(message: message)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 72)
                .allowsHitTesting(false)
                .animation(.spring(duration: 0.3), value: message)
            }
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { message = nil }
            }
    }
}

extension View {
    /// Shows the message as a capsule at the bottom for 2 s, then clears the binding.
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
