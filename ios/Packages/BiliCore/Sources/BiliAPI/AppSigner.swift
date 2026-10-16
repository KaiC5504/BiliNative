import Foundation

/// The app API's request signing: the secret is appended to the sorted, percent-encoded query and hashed.
/// The key pair is a parameter because it comes from a build-time secret and never lives in this package.
public struct AppSigner: Sendable {
    private let appKey: String
    private let appSecret: String

    public init(appKey: String, appSecret: String) {
        self.appKey = appKey
        self.appSecret = appSecret
    }

    public func signed(_ params: [String: String], ts: Int) -> [String: String] {
        var fields = params
        fields["appkey"] = appKey
        fields["ts"] = String(ts)
        fields["sign"] = MD5.hex(WBI.encodeQuery(fields) + appSecret)
        return fields
    }
}
