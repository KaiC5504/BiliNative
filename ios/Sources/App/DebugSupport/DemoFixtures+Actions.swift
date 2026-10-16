#if DEBUG
import Foundation

/// Invented answers for the actions: every write succeeds, 三连 spends two coins, and `page-actions-active` opens
/// a video this account has already liked, coined and favourited.
enum ActionsFixtures {
    static let activeScreen = "page-actions-active"

    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        switch url.path {
        case "/x/web-interface/archive/relation":
            // Listed before the 简介's fixtures, which answer the relation of every other demo screen.
            guard UserDefaults.standard.string(forKey: "DemoScreen") == activeScreen else { return nil }
            return DemoFixtures.ok(#"{"attention":false,"favorite":true,"season_fav":false,"like":true,"dislike":false,"coin":1}"#)
        case "/x/web-interface/archive/like", "/x/relation/modify":
            return DemoFixtures.ok("null")
        case "/x/web-interface/archive/like/triple":
            return DemoFixtures.ok(#"{"like":true,"coin":true,"fav":true,"multiply":2,"id_list":[3001],"prompt":false}"#)
        case "/x/web-interface/coin/add":
            return DemoFixtures.ok(#"{"like":false}"#)
        case "/site/getCoin":
            return DemoFixtures.ok(#"{"money":873.0}"#)
        case "/x/v3/fav/folder/created/list-all":
            return DemoFixtures.ok(folders)
        case "/x/v3/fav/resource/batch-deal":
            return DemoFixtures.ok(#"{"prompt":false,"ga_data":null,"toast_msg":""}"#)
        case "/x/v3/fav/folder/add":
            return DemoFixtures.ok(#"{"id":3004,"fid":30,"mid":10001,"attr":2,"title":"新建的收藏夹","fav_state":0,"media_count":0}"#)
        case "/x/web-interface/share/add":
            return DemoFixtures.ok("149")
        default:
            return nil
        }
    }

    private static let folders = """
    {"count":3,"list":[
      {"id":3001,"fid":1,"mid":10001,"attr":0,"title":"默认收藏夹","fav_state":0,"media_count":128},
      {"id":3002,"fid":2,"mid":10001,"attr":2,"title":"演示：动画","fav_state":0,"media_count":36},
      {"id":3003,"fid":3,"mid":10001,"attr":3,"title":"演示：私密","fav_state":0,"media_count":5}]}
    """
}
#endif
