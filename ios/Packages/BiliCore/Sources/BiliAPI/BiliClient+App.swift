import Foundation

public enum TVLoginState: Equatable, Sendable {
    case waiting
    case expired
    case confirmed(accessToken: String, mid: Int64)
}

private struct TVAuthCode: Decodable {
    let url: String
    let authCode: String

    enum CodingKeys: String, CodingKey {
        case url
        case authCode = "auth_code"
    }
}

private struct TVToken: Decodable {
    let accessToken: String
    let mid: Int64

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case mid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        mid = try container.decode(Int64.self, forKey: .mid)
        guard !accessToken.isEmpty else { throw missing("access_token", decoder) }
    }
}

/// The app API (and the passport TV login that issues its token) wants a signature and an access token, not cookies.
extension BiliClient {
    public static let passport = "https://passport.bilibili.com"
    public static let appAPI = "https://app.bilibili.com"

    /// The URL is Bilibili's confirm page; the user opens it in a signed-in web view and taps 确认登录.
    public func tvAuthCode(signer: AppSigner) async throws -> (url: String, authCode: String) {
        let form = signer.signed(["local_id": "0"], ts: timestamp)
        let code: TVAuthCode = try await post("/x/passport-tv-login/qrcode/auth_code", form: form,
                                              host: Self.passport, cookies: false)
        return (code.url, code.authCode)
    }

    public func tvPoll(signer: AppSigner, authCode: String) async throws -> TVLoginState {
        let form = signer.signed(["auth_code": authCode, "local_id": "0"], ts: timestamp)
        let envelope: BiliEnvelope<TVToken> = try await postEnvelope("/x/passport-tv-login/qrcode/poll", form: form,
                                                                     referer: nil, host: Self.passport, cookies: false)
        switch envelope.code {
        case 0:
            guard let token = envelope.data else { throw BiliError.decoding("tv login: confirmed without a token") }
            return .confirmed(accessToken: token.accessToken, mid: token.mid)
        case 86039, 86090:
            return .waiting
        case 86038:
            return .expired
        default:
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
    }

    /// `on: true` dislikes the video, `on: false` takes it back.
    public func dislike(aid: Int64, on: Bool, accessToken: String, signer: AppSigner) async throws {
        let form = signer.signed(["aid": String(aid), "dislike": on ? "0" : "1", "access_key": accessToken], ts: timestamp)
        try await post("/x/v2/view/dislike", form: form, host: Self.appAPI, cookies: false)
    }

    private var timestamp: Int { Int(now().timeIntervalSince1970) }
}
