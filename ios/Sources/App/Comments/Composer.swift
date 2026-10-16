import SwiftUI
import UIKit
import BiliAPI

/// The comment composer (14): a white sheet over the dimmed page with the text, the expand arrow, a toolbar
/// (转到动态, keyboard/emote toggle, 发布), and the keyboard or the emote panel under it. It follows the keyboard by
/// hand like the danmaku bar, since the page keeps the keyboard from squeezing it while the composer is open.
struct Composer: View {
    @Bindable var model: ComposerModel
    let onClose: () -> Void
    #if DEBUG
    /// Screenshots show no software keyboard, so the demo opens without asking for one.
    var demo = false
    #endif

    @Environment(AppEnvironment.self) private var env
    @FocusState private var focused: Bool
    @State private var expanded = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var shown = false
    @State private var emotesFailed = false

    private typealias T = Theme.Composer

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            ZStack(alignment: .bottom) {
                T.dim
                    .opacity(shown ? 1 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                VStack(spacing: 0) {
                    editor
                    toolbar
                    if model.showingEmotes {
                        EmotePanel(packages: env.emotePackages, recent: model.recent, bottomInset: insets.bottom,
                                   onRetry: emotesFailed ? { Task { await loadEmotes() } } : nil,
                                   onPick: model.insert)
                    } else {
                        T.sheet
                            .frame(height: max(keyboardHeight, insets.bottom))
                    }
                }
                .background(T.sheet, in: UnevenRoundedRectangle(topLeadingRadius: T.sheetRadius, topTrailingRadius: T.sheetRadius))
                .offset(y: shown ? 0 : geometry.size.height)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                keyboardChanged(note, screenHeight: geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .onChange(of: keyboardHeight) { _, height in
            if height > 0 { model.showingEmotes = false }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { Task { await leaveEmotesIfNoKeyboard() } }
        }
        .task {
            withAnimation(.smooth(duration: 0.25)) { shown = true }
            if !isDemo, !model.showingEmotes {
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
            await loadEmotes()
        }
    }

    private var isDemo: Bool {
        #if DEBUG
        return demo
        #else
        return false
        #endif
    }

    private var editor: some View {
        TextField("", text: $model.text, prompt: Text(model.placeholder).foregroundStyle(T.placeholder), axis: .vertical)
            .font(T.editorFont)
            .foregroundStyle(Theme.text)
            .tint(T.accent)
            .lineLimit(expanded ? 10 : 2)
            .focused($focused)
            .padding(.top, T.editorTop)
            .padding(.leading, T.editorLeading)
            .padding(.trailing, T.editorTrailing)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: expanded ? T.expandedEditorHeight : T.editorHeight, alignment: .top)
            // The field is only as tall as its lines; the rest of the editor area still brings up the keyboard.
            .background(T.sheet.onTapGesture { focused = true })
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: T.expandIcon))
                        .foregroundStyle(T.expand)
                        .frame(width: T.editorTrailing, height: T.toolbarHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "收起" : "展开")
            }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                model.syncToDynamic.toggle()
            } label: {
                HStack(spacing: T.syncGap) {
                    ZStack {
                        if model.syncToDynamic {
                            Circle().fill(T.accent)
                            Image(systemName: "checkmark")
                                .font(.system(size: T.syncCircle * 0.6, weight: .bold))
                                .foregroundStyle(T.publishText)
                        } else {
                            Circle().strokeBorder(T.syncRing, lineWidth: 1)
                        }
                    }
                    .frame(width: T.syncCircle, height: T.syncCircle)
                    Text("转到动态")
                        .font(T.syncFont)
                        .foregroundStyle(T.tool)
                }
                .frame(width: T.syncWidth, height: T.toolbarHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(model.syncToDynamic ? .isSelected : [])
            Button(action: toggleEmotes) {
                Group {
                    if model.showingEmotes {
                        Image(systemName: "keyboard")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: T.keyboardIcon.width, height: T.keyboardIcon.height)
                            .foregroundStyle(T.accent)
                    } else {
                        EmoteFace()
                            .stroke(T.tool, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                            .frame(width: T.keyboardIcon.width, height: T.keyboardIcon.width)
                    }
                }
                .frame(width: T.toggleWidth, height: T.toolbarHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(model.showingEmotes ? "键盘" : "表情")
            Spacer(minLength: 8)
            Button(action: publish) {
                ZStack {
                    if model.posting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(T.publishText)
                    } else {
                        Text("发布")
                            .font(T.publishFont)
                            .foregroundStyle(T.publishText)
                    }
                }
                .frame(width: T.publish.width, height: T.publish.height)
                .background(model.canPost ? T.accent : T.accentFaded, in: Capsule())
            }
            .disabled(!model.canPost)
        }
        .buttonStyle(.plain)
        .padding(.leading, T.syncLeading)
        .padding(.trailing, T.publishTrailing)
        .frame(height: T.toolbarHeight)
    }

    private func toggleEmotes() {
        if model.showingEmotes {
            focused = true
        } else {
            model.showingEmotes = true
            focused = false
        }
    }

    private func publish() {
        Task {
            if await model.post() { close() }
        }
    }

    private func close() {
        focused = false
        withAnimation(.smooth(duration: 0.2)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            onClose()
        }
    }

    private func loadEmotes() async {
        emotesFailed = false
        await env.loadEmotePackages()
        emotesFailed = env.emotePackages.isEmpty
    }

    private func keyboardChanged(_ note: Notification, screenHeight: CGFloat) {
        guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeOut(duration: duration)) { keyboardHeight = max(0, screenHeight - end.minY) }
    }

    /// A hardware keyboard shows no software one, so the panel would never give way otherwise.
    private func leaveEmotesIfNoKeyboard() async {
        try? await Task.sleep(for: .milliseconds(600))
        if focused, keyboardHeight == 0 { model.showingEmotes = false }
    }
}
