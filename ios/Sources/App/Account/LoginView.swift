import SwiftUI
import WebKit
import BiliAPI
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
        let store = configuration.websiteDataStore.httpCookieStore
        context.coordinator.store = store
        context.coordinator.start(webView, in: store)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onLogin: ([String: String]) -> Void
        weak var store: WKHTTPCookieStore?
        private var finished = false

        init(onLogin: @escaping ([String: String]) -> Void) {
            self.onLogin = onLogin
        }

        /// A SESSDATA left over from an expired login would otherwise count as a fresh login at once,
        /// so the page only loads after the old bilibili.com cookies are gone.
        func start(_ webView: WKWebView, in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak webView, weak cookieStore] cookies in
                let stale = cookies.filter { BiliHosts.isBilibili($0.domain) }
                var remaining = stale.count
                let begin = {
                    guard let webView, let cookieStore else { return }
                    cookieStore.add(self)
                    webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
                }
                guard remaining > 0 else { return begin() }
                for cookie in stale {
                    cookieStore?.delete(cookie) {
                        remaining -= 1
                        if remaining == 0 { begin() }
                    }
                }
            }
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
                let bilibili = cookies.filter { BiliHosts.isBilibili($0.domain) }
                guard bilibili.contains(where: { $0.name == "SESSDATA" && !$0.value.isEmpty }) else { return }
                self.finished = true
                self.onLogin(Dictionary(bilibili.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first }))
            }
        }
    }
}
