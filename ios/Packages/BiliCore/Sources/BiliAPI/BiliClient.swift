import Foundation
import BiliShared
import DevLog

public final class BiliClient: @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    public static let referer = "https://www.bilibili.com/"
    public static var mediaHeaders: [String: String] { ["User-Agent": userAgent, "Referer": referer] }
    /// DASH | HDR | 4K | Dolby audio | Dolby Vision | 8K | AV1.
    public static let dashFnval = 4048

    private static let api = "https://api.bilibili.com"

    private let transport: HTTPTransport
    public let cookies: CookieJar
    private let now: @Sendable () -> Date
    private let logger: Logger
    private let wbiCache = Locked<(day: String, mixin: String)?>(nil)

    public init(transport: HTTPTransport, cookies: CookieJar, now: @escaping @Sendable () -> Date = { Date() }, logger: Logger = .shared) {
        self.transport = transport
        self.cookies = cookies
        self.now = now
        self.logger = logger
    }

    /// A logged-out reply (-101) still carries the WBI keys, so it is returned, not thrown.
    public func nav() async throws -> NavInfo {
        let envelope: BiliEnvelope<NavInfo> = try await get("/x/web-interface/nav", query: [:], signed: false)
        guard let nav = envelope.data else {
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
        let imgKey = WBI.key(fromURL: nav.imgURL)
        let subKey = WBI.key(fromURL: nav.subURL)
        let mixin = WBI.mixinKey(imgKey: imgKey, subKey: subKey)
        let valid = !imgKey.isEmpty && !subKey.isEmpty && mixin.count == 32
        wbiCache.withLock { $0 = valid ? (today(), mixin) : nil }
        return nav
    }

    /// The web API answers 412 to requests without the website's fingerprint cookies.
    public func ensureRiskCookies() async throws {
        guard cookies.value("buvid3") == nil || cookies.value("buvid4") == nil else { return }
        let envelope: BiliEnvelope<SPIInfo> = try await get("/x/frontend/finger/spi", query: [:], signed: false)
        let spi = try checked(envelope)
        if cookies.value("buvid3") == nil { cookies.set("buvid3", spi.b3) }
        if cookies.value("buvid4") == nil { cookies.set("buvid4", spi.b4) }
    }

    public func view(bvid: String) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await get("/x/web-interface/view", query: ["bvid": bvid], signed: false)
        return try checked(envelope)
    }

    public func view(aid: Int64) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await get("/x/web-interface/view", query: ["aid": String(aid)], signed: false)
        return try checked(envelope)
    }

    public func resolve(_ link: VideoLink) async throws -> (view: VideoView, page: Int?) {
        switch link {
        case .bvid(let id, let page):
            return (try await view(bvid: id), page)
        case .aid(let id, let page):
            return (try await view(aid: id), page)
        case .short(let url):
            // The link parser accepts http:// share links, which App Transport Security would block.
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw BiliError.invalidLink }
            components.scheme = "https"
            guard let secure = components.url else { throw BiliError.invalidLink }
            let response = try await transport.send(HTTPRequest(url: secure, headers: ["User-Agent": Self.userAgent]))
            logger.info(.api, "resolve short link", ["host": .init(secure.host ?? ""), "status": .init(response.status)])
            guard let next = LinkParser.parse(response.finalURL.absoluteString), !next.isShort else {
                throw BiliError.invalidLink
            }
            return try await resolve(next)
        }
    }

    public func playURL(bvid: String, cid: Int64, quality: Int) async throws -> PlayURLInfo {
        let query = ["bvid": bvid, "cid": String(cid), "qn": String(quality), "fnval": String(Self.dashFnval), "fnver": "0", "fourk": "1"]
        let envelope: BiliEnvelope<PlayURLInfo> = try await get("/x/player/wbi/playurl", query: query, signed: true)
        let info = try checked(envelope)
        guard info.dash != nil else { throw BiliError.notDash }
        return info
    }

    private func mixinKey() async throws -> String {
        if let cached = wbiCache.current, cached.day == today() { return cached.mixin }
        _ = try await nav()
        guard let cached = wbiCache.current, cached.day == today() else {
            throw BiliError.decoding("WBI keys missing or malformed in nav")
        }
        return cached.mixin
    }

    private func today() -> String {
        let seconds = Int(now().timeIntervalSince1970)
        return String(seconds / 86_400)
    }

    private func checked<T>(_ envelope: BiliEnvelope<T>) throws -> T {
        guard envelope.code == 0, let data = envelope.data else {
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String], signed: Bool, retried: Bool = false) async throws -> BiliEnvelope<T> {
        let queryString: String
        if signed {
            let key = try await mixinKey()
            queryString = WBI.signedQuery(query, mixinKey: key, wts: Int(now().timeIntervalSince1970))
        } else {
            queryString = WBI.encodeQuery(query)
        }
        guard let url = URL(string: Self.api + path + (queryString.isEmpty ? "" : "?" + queryString)) else {
            throw BiliError.invalidLink
        }
        var headers = ["User-Agent": Self.userAgent, "Referer": Self.referer, "Accept": "application/json"]
        if let cookie = cookies.headerValue { headers["Cookie"] = cookie }
        let started = Date()
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url, headers: headers))
        } catch {
            logger.error(.api, path, ["error": .init(error.localizedDescription)])
            throw error
        }
        let ms = Date().timeIntervalSince(started) * 1000
        guard (200..<300).contains(response.status) else {
            logger.warn(.api, path, ["status": .init(response.status), "ms": .init(ms.rounded())])
            // 412 is risk control; fresh fingerprint cookies usually clear it once.
            if response.status == 412 && !retried && path != "/x/frontend/finger/spi" {
                cookies.remove("buvid3")
                cookies.remove("buvid4")
                try await ensureRiskCookies()
                return try await get(path, query: query, signed: signed, retried: true)
            }
            throw BiliError.http(response.status)
        }
        do {
            let envelope = try JSONDecoder().decode(BiliEnvelope<T>.self, from: response.body)
            logger.info(.api, path, ["status": .init(response.status), "code": .init(envelope.code), "ms": .init(ms.rounded())])
            return envelope
        } catch {
            logger.error(.api, "\(path) decode failed", ["error": .init(String(describing: error))])
            throw BiliError.decoding(String(describing: error))
        }
    }
}
