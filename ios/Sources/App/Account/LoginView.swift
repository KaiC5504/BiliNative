import SwiftUI
import WebKit
import DevLog

/// Bilibili's own login page (password, SMS or QR; it handles its own captcha). The app never sees
/// the password: it only copies the bilibili.com cookies once `SESSDATA` appears.
struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView { cookies in
                Task {
                    await env.didLogin(cookies)
                    dismiss()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("登录哔哩哔哩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    let onLogin: ([String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLogin: onLogin)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.store = configuration.websiteDataStore.httpCookieStore
        webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onLogin: ([String: String]) -> Void
        weak var store: WKHTTPCookieStore?
        private var finished = false

        init(onLogin: @escaping ([String: String]) -> Void) {
            self.onLogin = onLogin
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            check(cookieStore)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Logger.shared.info(.ui, "login page", ["url": .init(webView.url?.absoluteString ?? "")])
            if let store { check(store) }
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished else { return }
                let bilibili = cookies.filter { Self.isBilibili($0.domain) }
                guard bilibili.contains(where: { $0.name == "SESSDATA" && !$0.value.isEmpty }) else { return }
                self.finished = true
                self.onLogin(Dictionary(bilibili.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first }))
            }
        }

        /// A plain suffix test would also accept hosts like "evilbilibili.com".
        private static func isBilibili(_ domain: String) -> Bool {
            let host = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
        }
    }
}
