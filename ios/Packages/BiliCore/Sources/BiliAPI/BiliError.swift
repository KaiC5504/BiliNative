public enum BiliError: Error, Equatable, Sendable {
    case http(Int)
    case api(code: Int, message: String)
    case decoding(String)
    case notDash
    case invalidLink

    public var needsLogin: Bool {
        if case .api(-101, _) = self { return true }
        return false
    }

    public var userMessage: String {
        switch self {
        case .http(412):
            return "B 站暂时拒绝了请求（风控），稍后再试"
        case .http(let status):
            return "网络请求失败（HTTP \(status)）"
        case .api(-101, _):
            return "需要登录"
        case .api(-352, _), .api(-412, _):
            return "请求过于频繁，请稍后再试"
        case .api(-404, _), .api(62002, _), .api(62004, _):
            return "视频不存在或已被删除"
        case .api(let code, let message):
            return "B 站返回错误 \(code)：\(message)"
        case .decoding:
            return "B 站返回的数据无法解析"
        case .notDash:
            return "这个视频不是 DASH 格式，暂不支持"
        case .invalidLink:
            return "没有找到视频链接"
        }
    }
}
