import Foundation
import Observation
import WebKit
import BiliAPI
import BiliShared
import Ripper
import LocalHTTP
import DevLog

@MainActor
@Observable
final class AppEnvironment {
    enum Account: Equatable {
        case unknown
        case loggedOut
        case loggedIn(name: String, vip: Bool)
        /// Cookies exist but Bilibili no longer accepts them (nav answered isLogin == false).
        case expired
    }

    let settings = AppSettings()
    @ObservationIgnored let cookies: CookieJar
    @ObservationIgnored let client: BiliClient
    @ObservationIgnored let auto = AutoConcurrency()
    @ObservationIgnored let router: PlaybackRouter
    @ObservationIgnored let server: LocalServer
    @ObservationIgnored let directLoader = DirectPlaylistLoader()
    @ObservationIgnored let transport = URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
    @ObservationIgnored let codecMemory = CodecMemory()
    private(set) var account: Account = .unknown
    /// The last nav call failed (network, not a verdict), so `account` is still `.unknown`.
    private(set) var accountCheckFailed = false

    /// Serial, and each write reads the jar's current state: onChange callbacks from concurrent
    /// requests can arrive out of order, so a callback's own snapshot may already be stale.
    @ObservationIgnored private let persistQueue: DispatchQueue
    /// Set when the Keychain read failed: stored cookies may still exist, so nothing is written
    /// back until a read succeeds or the user logs in or out.
    @ObservationIgnored private let persistBlocked: Locked<Bool>

    init() {
        let jar = CookieJar()
        let queue = DispatchQueue(label: "bilinative.cookies.persist")
        let blocked = Locked(false)
        switch KeychainStore.load() {
        case .cookies(let stored): jar.replaceAll(stored)
        case .notFound: break
        case .failed: blocked.withLock { $0 = true }
        }
        jar.onChange = { [weak jar] _ in
            queue.async {
                guard let jar, !blocked.current else { return }
                KeychainStore.saveCookies(jar.all)
            }
        }
        persistQueue = queue
        persistBlocked = blocked
        cookies = jar
        client = BiliClient(transport: URLSessionHTTPTransport(), cookies: jar)
        let router = PlaybackRouter()
        let server = LocalServer(router: router)
        // Set before the listener starts: onStop is read on the server's queue. A controller acts on the
        // notification only while its BTR item plays, so a stop after playback ended changes nothing.
        server.onStop = { [weak server] in
            guard let server else { return }
            NotificationCenter.default.post(name: .localServerStopped, object: server)
        }
        self.router = router
        self.server = server
    }

    func startServices() async {
        do {
            try await server.start()
        } catch {
            Logger.shared.error(.server, "server did not start; playback will use direct mode", ["error": .init(String(describing: error))])
        }
    }

    func playbackEnvironment(bvid: String, cid: Int64) -> PlaybackEnvironment {
        PlaybackEnvironment(provider: BiliPlayURLProvider(client: client, bvid: bvid, cid: cid), router: router, server: server,
                            directLoader: directLoader, transport: transport, auto: auto, nodeMode: settings.nodeChoice.mode,
                            policy: .bilibili, ripperConfig: RipperConfig(), codecMemory: codecMemory, mediaHeaders: BiliClient.mediaHeaders)
    }

    /// Returns false when Bilibili could not be asked (network error); `account` then keeps its last value.
    @discardableResult
    func refreshAccount() async -> Bool {
        retryBlockedKeychainLoad()
        do {
            try await client.ensureRiskCookies()
            let nav = try await client.nav()
            accountCheckFailed = false
            if nav.isLogin {
                account = .loggedIn(name: nav.uname ?? "", vip: nav.isVip)
                Logger.shared.info(.app, "account", ["user": .init(nav.mid.map(Redactor.mid) ?? "?"), "vip": .init(nav.isVip)])
            } else {
                account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            Logger.shared.warn(.app, "nav failed", ["error": .init(String(describing: error))])
            if account == .unknown {
                if cookies.value("SESSDATA") == nil {
                    account = .loggedOut
                } else {
                    accountCheckFailed = true
                }
            }
            return false
        }
    }

    func didLogin(_ webCookies: [String: String]) async {
        var merged = cookies.all
        merged.merge(webCookies) { _, new in new }
        persistBlocked.withLock { $0 = false }
        cookies.replaceAll(merged)
        account = .unknown
        accountCheckFailed = false
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt))) }
            if await refreshAccount() { return }
        }
    }

    func logout() async {
        persistBlocked.withLock { $0 = false }
        cookies.removeAll()
        persistQueue.async { KeychainStore.deleteCookies() }
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        accountCheckFailed = false
        account = .loggedOut
    }

    private func retryBlockedKeychainLoad() {
        guard persistBlocked.current else { return }
        switch KeychainStore.load() {
        case .cookies(let stored):
            var merged = stored
            merged.merge(cookies.all) { _, new in new }
            persistBlocked.withLock { $0 = false }
            cookies.replaceAll(merged)
        case .notFound:
            persistBlocked.withLock { $0 = false }
            cookies.replaceAll(cookies.all)
        case .failed:
            break
        }
    }
}
