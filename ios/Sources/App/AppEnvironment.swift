import Foundation
import Observation
import WebKit
import BiliAPI
import DevLog

@MainActor
@Observable
final class AppEnvironment {
    enum Account: Equatable {
        case unknown
        case loggedOut
        case loggedIn(name: String, vip: Bool)
        /// Cookies exist but Bilibili no longer accepts them.
        case expired
    }

    let settings = AppSettings()
    @ObservationIgnored let cookies: CookieJar
    @ObservationIgnored let client: BiliClient
    private(set) var account: Account = .unknown

    /// Serial, and each write reads the jar's current state: onChange callbacks from concurrent
    /// requests can arrive out of order, so a callback's own snapshot may already be stale.
    @ObservationIgnored private let persistQueue: DispatchQueue

    init() {
        let jar = CookieJar(KeychainStore.loadCookies())
        let queue = DispatchQueue(label: "bilinative.cookies.persist")
        persistQueue = queue
        jar.onChange = { [weak jar] _ in
            queue.async {
                guard let jar else { return }
                KeychainStore.saveCookies(jar.all)
            }
        }
        cookies = jar
        client = BiliClient(transport: URLSessionHTTPTransport(), cookies: jar)
    }

    func refreshAccount() async {
        do {
            try await client.ensureRiskCookies()
            let nav = try await client.nav()
            if nav.isLogin {
                account = .loggedIn(name: nav.uname ?? "", vip: nav.isVip)
                Logger.shared.info(.app, "account", ["user": .init(nav.mid.map(Redactor.mid) ?? "?"), "vip": .init(nav.isVip)])
            } else {
                account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired
            }
        } catch {
            Logger.shared.warn(.app, "nav failed", ["error": .init(String(describing: error))])
            if account == .unknown { account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired }
        }
    }

    func didLogin(_ webCookies: [String: String]) async {
        var merged = cookies.all
        merged.merge(webCookies) { _, new in new }
        cookies.replaceAll(merged)
        await refreshAccount()
    }

    func logout() async {
        cookies.removeAll()
        persistQueue.async { KeychainStore.deleteCookies() }
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        account = .loggedOut
    }
}
