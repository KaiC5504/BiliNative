import SwiftUI
import UIKit

/// The dark input bar above the keyboard (22). The A button swaps the keyboard for the style panel (23).
/// It fills the page so a tap on the video behind closes it, and it follows the keyboard by hand: the
/// page ignores safe areas in full screen, so the system's keyboard avoidance would not reach it.
struct DanmakuSendBar: View {
    @Bindable var model: DanmakuSendModel
    let onClose: () -> Void
    #if DEBUG
    var demo: Demo? = nil

    /// Simulator screenshots do not show the software keyboard, so the demo draws a stand-in.
    enum Demo { case keyboard, style }
    #endif

    @FocusState private var focused: Bool
    @State private var showsStyle = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var lastKeyboardHeight: CGFloat = 0
    @State private var message: String?
    @AppStorage("danmaku.styleHintSeen") private var styleHintSeen = false

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let landscape = geometry.size.width > geometry.size.height
            let panelHeight = lastKeyboardHeight > 0 ? lastKeyboardHeight
                : (landscape ? DanmakuSendTheme.landscapePanelHeight : DanmakuSendTheme.portraitPanelHeight)
            let areaHeight = max(showsStyle || isDemoKeyboard ? panelHeight : keyboardHeight, insets.bottom)
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                VStack(spacing: 0) {
                    bar(insets: insets)
                    ZStack(alignment: .top) {
                        DanmakuSendTheme.area
                        if showsStyle {
                            DanmakuStylePanel(model: model, onVipOnly: { show("开通大会员后可使用") })
                                .padding(.leading, insets.leading + 12)
                                .padding(.trailing, insets.trailing + 12)
                        } else if isDemoKeyboard {
                            keyboardStandIn
                        }
                    }
                    .frame(height: areaHeight)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardChanged(note, screenHeight: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .onChange(of: keyboardHeight) { _, height in
            if height > 0 { showsStyle = false }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { Task { await leaveStyleIfNoKeyboard() } }
        }
        .onChange(of: model.needsLogin) { _, needsLogin in
            if needsLogin { show("需要登录") }
        }
        .task {
            #if DEBUG
            if let demo {
                showsStyle = demo == .style
                return
            }
            #endif
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }

    private var isDemoKeyboard: Bool {
        #if DEBUG
        return demo == .keyboard
        #else
        return false
        #endif
    }

    private func bar(insets: EdgeInsets) -> some View {
        HStack(spacing: 0) {
            Button(action: toggleStyle) {
                ZStack {
                    UnderlinedA()
                        .stroke(showsStyle ? DanmakuSendTheme.accent : .white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 14.6, height: 17.75)
                    if !showsStyle && !styleHintSeen {
                        Circle()
                            .fill(.red)
                            .frame(width: 5, height: 5)
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(width: 30, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("弹幕样式")
            field
                .padding(.leading, 6)
            Button(action: send) {
                Group {
                    if model.sending {
                        ProgressView().tint(.white)
                    } else {
                        SendArrow()
                            .stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                    }
                }
                .frame(width: 40, height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发送")
        }
        .padding(.leading, insets.leading + 6)
        .padding(.trailing, insets.trailing + 1)
        .frame(height: 42)
        .background(DanmakuSendTheme.bar)
        .overlay(alignment: .top) {
            if let message {
                Toast(message: message)
                    .offset(y: -46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: message)
        .task(id: message) {
            guard message != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { message = nil }
        }
    }

    private var field: some View {
        TextField("", text: $model.text,
                  prompt: Text("发个友善的弹幕见证当下").foregroundStyle(DanmakuSendTheme.placeholder))
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .tint(DanmakuSendTheme.accent)
            .focused($focused)
            .submitLabel(.send)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(send)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.white, in: Capsule())
    }

    private var keyboardStandIn: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<(row == 3 ? 4 : 10), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white.opacity(0.18))
                            .frame(height: 32)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private func toggleStyle() {
        styleHintSeen = true
        if showsStyle {
            focused = true
        } else {
            showsStyle = true
            focused = false
        }
    }

    private func send() {
        guard model.canSend else { return }
        Task {
            if let failure = await model.send() {
                show(failure)
            } else {
                onClose()
            }
        }
    }

    private func show(_ text: String) {
        message = text
    }

    private func keyboardChanged(_ note: Notification, screenHeight: CGFloat) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let height = max(0, screenHeight - end.minY)
        withAnimation(.easeOut(duration: duration)) { keyboardHeight = height }
        if height > 0 { lastKeyboardHeight = height }
    }

    /// A hardware keyboard shows no software one, so the panel would never give way otherwise.
    private func leaveStyleIfNoKeyboard() async {
        try? await Task.sleep(for: .milliseconds(600))
        if focused, keyboardHeight == 0 { showsStyle = false }
    }
}

/// An A with a line under it, the style button's glyph.
private struct UnderlinedA: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.03, y: rect.minY + h * 0.8))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.486, y: rect.minY + h * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.955, y: rect.minY + h * 0.8))
        path.move(to: CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.77, y: rect.minY + h * 0.52))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.99))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.99))
        return path
    }
}

/// The outlined paper plane of the send button.
private struct SendArrow: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 18, y: rect.minY + rect.height * y / 18)
        }
        var path = Path()
        path.move(to: point(1.8, 6.6))
        path.addLine(to: point(1.0, 1.6))
        path.addLine(to: point(17, 8))
        path.addLine(to: point(1.0, 16.4))
        path.addLine(to: point(2.8, 10))
        path.addLine(to: point(11, 9.2))
        return path
    }
}
