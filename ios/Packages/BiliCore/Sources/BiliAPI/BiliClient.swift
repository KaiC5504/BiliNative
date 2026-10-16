import Foundation
import BiliShared
import DevLog

public final class BiliClient: @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    public static let referer = "https://www.bilibili.com/"
    public static var mediaHeaders: [String: String] { ["User-Agent": userAgent, "Referer": referer] }
    /// DASH | HDR | 4K | Dolby audio | Dolby Vision | 8K | AV1.
    public static let dashFnval = 4048

    public static let api = "https://api.bilibili.com"
    private static let origin = "https://www.bilibili.com"

    private let transport: HTTPTransport
    public let cookies: CookieJar
    let now: @Sendable () -> Date
    private let logger: Logger
    private let wbiCache = Locked<(day: String, mixin: String)?>(nil)

    public init(transport: HTTPTransport, cookies: CookieJar, now: @escaping @Sendable () -> Date = { Date() }, logger: Logger = .shared) {
        self.transport = transport
        self.cookies = cookies
        self.now = now
        self.logger = logger
    }

    /// The cookie every write call must echo back as the `csrf` form field.
    public var csrf: String? {
        cookies.value("bili_jct").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A logged-out reply (-101) still carries the WBI keys, so it is returned, not thrown.
    public func nav() async throws -> NavInfo {
        let envelope: BiliEnvelope<NavInfo> = try await getEnvelope("/x/web-interface/nav", query: [:], signed: false)
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
        let envelope: BiliEnvelope<SPIInfo> = try await getEnvelope("/x/frontend/finger/spi", query: [:], signed: false)
        let spi = try checked(envelope)
        if cookies.value("buvid3") == nil { cookies.set("buvid3", spi.b3) }
        if cookies.value("buvid4") == nil { cookies.set("buvid4", spi.b4) }
    }

    public func view(bvid: String) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await getEnvelope("/x/web-interface/view", query: ["bvid": bvid], signed: false)
        return try checked(envelope)
    }

    public func view(aid: Int64) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await getEnvelope("/x/web-interface/view", query: ["aid": String(aid)], signed: false)
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
        let envelope: BiliEnvelope<PlayURLInfo> = try await getEnvelope("/x/player/wbi/playurl", query: query, signed: true)
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

    func checked<T>(_ envelope: BiliEnvelope<T>) throws -> T {
        guard envelope.code == 0, let data = envelope.data else {
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
        return data
    }

    public func get<T: Decodable>(_ path: String, query: [String: String], signed: Bool,
                                  host: String = BiliClient.api) async throws -> T {
        let envelope: BiliEnvelope<T> = try await getEnvelope(path, query: query, signed: signed, host: host)
        return try checked(envelope)
    }

    /// For reads whose success may carry `data: null`, which is an empty result rather than an error.
    func getIfPresent<T: Decodable>(_ path: String, query: [String: String], signed: Bool) async throws -> T? {
        let envelope: BiliEnvelope<T> = try await getEnvelope(path, query: query, signed: signed)
        guard envelope.code == 0 else { throw BiliError.api(code: envelope.code, message: envelope.message ?? "") }
        return envelope.data
    }

    /// For endpoints that do not answer with the JSON envelope, such as the protobuf danmaku segments.
    public func getData(_ path: String, query: [String: String], signed: Bool,
                        host: String = BiliClient.api) async throws -> Data {
        let sent = try await send(method: "GET", path: path, query: query, signed: signed, host: host,
                                  form: nil, referer: nil, accept: "*/*")
        logger.info(.api, path, ["status": .init(sent.response.status), "ms": .init(sent.ms.rounded())])
        return sent.response.body
    }

    public func post<T: Decodable>(_ path: String, form: [String: String], referer: String? = nil,
                                   host: String = BiliClient.api, cookies: Bool = true) async throws -> T {
        let envelope: BiliEnvelope<T> = try await postEnvelope(path, form: form, referer: referer, host: host, cookies: cookies)
        return try checked(envelope)
    }

    /// For writes whose success carries no data (`data` may be null).
    public func post(_ path: String, form: [String: String], referer: String? = nil,
                     host: String = BiliClient.api, cookies: Bool = true) async throws {
        let envelope: BiliEnvelope<Ignored> = try await postEnvelope(path, form: form, referer: referer, host: host, cookies: cookies)
        guard envelope.code == 0 else { throw BiliError.api(code: envelope.code, message: envelope.message ?? "") }
    }

    private struct Ignored: Decodable {
        init(from decoder: Decoder) throws {}
    }

    private func getEnvelope<T: Decodable>(_ path: String, query: [String: String], signed: Bool,
                                           host: String = BiliClient.api) async throws -> BiliEnvelope<T> {
        let sent = try await send(method: "GET", path: path, query: query, signed: signed, host: host,
                                  form: nil, referer: nil, accept: "application/json")
        return try decodeEnvelope(sent, path: path)
    }

    func postEnvelope<T: Decodable>(_ path: String, form: [String: String], referer: String?,
                                    host: String, cookies: Bool = true) async throws -> BiliEnvelope<T> {
        let sent = try await send(method: "POST", path: path, query: [:], signed: false, host: host,
                                  form: form, referer: referer, accept: "application/json", cookies: cookies)
        return try decodeEnvelope(sent, path: path)
    }

    private func decodeEnvelope<T: Decodable>(_ sent: (response: HTTPResponse, ms: Double), path: String) throws -> BiliEnvelope<T> {
        do {
            let envelope = try JSONDecoder().decode(BiliEnvelope<T>.self, from: sent.response.body)
            logger.info(.api, path, ["status": .init(sent.response.status), "code": .init(envelope.code), "ms": .init(sent.ms.rounded())])
            return envelope
        } catch {
            logger.error(.api, "\(path) decode failed", ["error": .init(String(describing: error))])
            throw BiliError.decoding(String(describing: error))
        }
    }

    /// Logs the path only: the query and form can carry the csrf token or a comment the user typed.
    /// `cookies: false` is for the app API: no session cookies, no csrf field (its calls carry a signature and
    /// an access token instead), and no 412 retry, since fresh fingerprint cookies would not be sent anyway.
    private func send(method: String, path: String, query: [String: String], signed: Bool, host: String,
                      form: [String: String]?, referer: String?, accept: String, cookies sendCookies: Bool = true,
                      retried: Bool = false) async throws -> (response: HTTPResponse, ms: Double) {
        var body: Data?
        var headers = ["User-Agent": Self.userAgent, "Referer": referer ?? Self.referer, "Accept": accept]
        if let form {
            var fields = form
            if sendCookies {
                guard let token = csrf else { throw BiliError.api(code: -101, message: "账号未登录") }
                fields["csrf"] = token
                headers["Origin"] = Self.origin
            }
            body = FormEncoding.encode(fields)
            headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        }
        let queryString: String
        if signed {
            let key = try await mixinKey()
            queryString = WBI.signedQuery(query, mixinKey: key, wts: Int(now().timeIntervalSince1970))
        } else {
            queryString = WBI.encodeQuery(query)
        }
        guard let url = URL(string: host + path + (queryString.isEmpty ? "" : "?" + queryString)) else {
            throw BiliError.invalidLink
        }
        // The session cookies and the csrf token must never leave Bilibili's own hosts.
        if BiliHosts.isBilibili(url.host ?? "") {
            if sendCookies, let cookie = cookies.headerValue { headers["Cookie"] = cookie }
        } else if form != nil {
            throw BiliError.invalidLink
        }
        let started = Date()
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url, headers: headers, method: method, body: body))
        } catch {
            logger.error(.api, path, ["error": .init(error.localizedDescription)])
            throw error
        }
        let ms = Date().timeIntervalSince(started) * 1000
        guard (200..<300).contains(response.status) else {
            logger.warn(.api, path, ["status": .init(response.status), "ms": .init(ms.rounded())])
            // 412 is risk control; fresh fingerprint cookies usually clear it once.
            if response.status == 412 && !retried && sendCookies && path != "/x/frontend/finger/spi" {
                cookies.remove("buvid3")
                cookies.remove("buvid4")
                try await ensureRiskCookies()
                return try await send(method: method, path: path, query: query, signed: signed, host: host,
                                      form: form, referer: referer, accept: accept, cookies: sendCookies, retried: true)
            }
            throw BiliError.http(response.status)
        }
        return (response, ms)
    }
}
