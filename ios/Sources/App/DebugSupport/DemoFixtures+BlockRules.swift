#if DEBUG
import Foundation
import Danmaku

/// The 弹幕屏蔽词 endpoints, with invented rules. Adding answers with a fixed id and deleting with an empty
/// success, which is all the demo screens and tests need.
extension DemoFixtures {
    static let demoBlockRules = #"""
    {"rule":[
      {"id":101,"type":0,"filter":"剧透"},
      {"id":102,"type":0,"filter":"前方高能"},
      {"id":103,"type":1,"filter":"/^哈{3,}$/"},
      {"id":104,"type":2,"filter":"\#(MidHash.of(uid: 20_001))"}],
     "toast":"","valid":1,"ver":4}
    """#

    static func blockRules(_ url: URL, _ method: String) -> (Int, Data)? {
        switch (method, url.path) {
        case ("GET", "/x/dm/filter/user"):
            return ok(demoBlockRules)
        case ("POST", "/x/dm/filter/user/add"):
            return ok(#"{"id":9001}"#)
        case ("POST", "/x/dm/filter/user/del"):
            return (200, Data(#"{"code":0,"message":"0","ttl":1}"#.utf8))
        default:
            return nil
        }
    }
}
#endif
