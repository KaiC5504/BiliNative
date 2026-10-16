import SwiftUI
import WebKit
import BiliAPI

extension Theme {
    enum TVLogin {
        static let hintFont = Font.system(size: 14)
        static let hintSpacing: CGFloat = 6
        static let hintPadding: CGFloat = 16
        static let statusIcon: CGFloat = 44
        static let statusSpacing: CGFloat = 14
        static let buttonHeight: CGFloat = 44
        static let buttonWidth: CGFloat = 160
        static let buttonText = Color.white
    }
}

/// Explains the one-time confirmation and shows Bilibili's confirm page, which already has the login cookies.
/// The gate closes it as soon as the token is stored.
struct TVLoginSheet: View {
    let model: TVLoginModel
    /// Called once the token is stored, so the tap that asked for it can go through.
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card)
                .navigationTitle("授权不喜欢")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
        }
        .task { await model.start() }
        .onChange(of: model.state) { _, state in
            if state == .done { onDone() }
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .starting:
            ProgressView()
        case .confirming(let url):
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.TVLogin.hintSpacing) {
                    Text("不喜欢需要哔哩哔哩确认一次授权")
                        .foregroundStyle(Theme.text)
                    Text("在下方页面点「确认登录」")
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(Theme.TVLogin.hintFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.TVLogin.hintPadding)
                TVConfirmWebView(url: url)
            }
        case .expired:
            status(icon: "clock.badge.exclamationmark", title: "已过期", retry: true)
        case .failed(let message):
            status(icon: "exclamationmark.triangle", title: message, retry: true)
        case .unavailable:
            status(icon: "nosign", title: "此版本不支持不喜欢", retry: false)
        case .done:
            status(icon: "checkmark.circle.fill", title: "授权完成", retry: false, finish: true)
        }
    }

    private func status(icon: String, title: String, retry: Bool, finish: Bool = false) -> some View {
        VStack(spacing: Theme.TVLogin.statusSpacing) {
            Image(systemName: icon)
                .font(.system(size: Theme.TVLogin.statusIcon))
                .foregroundStyle(finish ? Theme.pink : Theme.secondaryText)
            Text(title)
                .font(Theme.TVLogin.hintFont)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if retry {
                button("重试") { Task { await model.start() } }
            } else if finish {
                button("完成") { dismiss() }
            }
        }
        .padding(Theme.TVLogin.hintPadding)
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.TVLogin.buttonText)
                .frame(width: Theme.TVLogin.buttonWidth, height: Theme.TVLogin.buttonHeight)
                .background(Theme.pink, in: Capsule())
        }
    }
}

private struct TVConfirmWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// The page carries the account's cookies, so it stays on Bilibili; any other link opens in Safari.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        static func staysInside(_ url: URL?) -> Bool {
            guard let url else { return false }
            if url.scheme == "about" { return true }
            guard url.scheme == "https" || url.scheme == "http", let host = url.host?.lowercased() else { return false }
            return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            // Frames inside the page load what it embeds; only the page itself is kept on Bilibili.
            if navigationAction.targetFrame?.isMainFrame == false || Self.staysInside(url) { return .allow }
            if let url { await UIApplication.shared.open(url) }
            return .cancel
        }

        /// `target=_blank` links: Bilibili's in this view, the rest in Safari.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                if Self.staysInside(url) { webView.load(URLRequest(url: url)) } else { UIApplication.shared.open(url) }
            }
            return nil
        }
    }
}

/// Presents the sheet when `requested` turns true, then resets it. A fresh model per presentation, so 重试 after
/// a dismissed attempt starts clean.
struct TVLoginGate: ViewModifier {
    @Binding var requested: Bool
    let makeModel: () -> TVLoginModel
    let onDone: () -> Void
    @State private var model: TVLoginModel?
    @State private var showing = false
    @State private var finished = false

    func body(content: Content) -> some View {
        content
            // The sheet closes before the tap that asked for it goes through: if that tap needs the sheet again or
            // shows a toast, nothing is in the way.
            .sheet(isPresented: $showing, onDismiss: {
                model?.cancel()
                if finished {
                    finished = false
                    onDone()
                }
            }) {
                if let model {
                    TVLoginSheet(model: model, onDone: {
                        finished = true
                        showing = false
                    })
                }
            }
            .onChange(of: requested) { _, asked in
                guard asked else { return }
                requested = false
                guard !showing else { return }
                InlineFirst.present {
                    guard !showing else { return }
                    model = makeModel()
                    showing = true
                }
            }
    }
}

extension View {
    func tvLoginGate(_ requested: Binding<Bool>, makeModel: @escaping () -> TVLoginModel,
                     onDone: @escaping () -> Void) -> some View {
        modifier(TVLoginGate(requested: requested, makeModel: makeModel, onDone: onDone))
    }
}
