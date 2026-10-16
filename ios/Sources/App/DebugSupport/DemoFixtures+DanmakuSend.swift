#if DEBUG
import Foundation

extension DemoFixtures {
    /// The answer to sending a danmaku: success with an invented id.
    static func danmakuPost(_ url: URL, _ method: String) -> (Int, Data)? {
        guard url.path == "/x/v2/dm/post" else { return nil }
        return ok(#"{"action":"","dmid":1700000000000000001,"dmid_str":"1700000000000000001"}"#)
    }
}
#endif
