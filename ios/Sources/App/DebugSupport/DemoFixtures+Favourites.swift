#if DEBUG
import Foundation

/// Invented answers for the coin dialog and the favourites sheet: 873.0 coins, three folders with the video already in
/// the default one, and every write succeeds.
enum FavouritesFixtures {
    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        switch url.path {
        case "/x/web-interface/archive/relation":
            // Listed before the other relation answers: no coin given yet, so both crates are open, and favourited, as
            // the default folder says.
            guard let screen = UserDefaults.standard.string(forKey: "DemoScreen"), ActionPromptsDemo.screens.contains(screen) else { return nil }
            return DemoFixtures.ok(#"{"attention":false,"favorite":true,"season_fav":false,"like":false,"dislike":false,"coin":0}"#)
        case "/site/getCoin":
            return DemoFixtures.ok(#"{"money":873.0}"#)
        case "/x/v3/fav/folder/created/list-all":
            return DemoFixtures.ok(folders)
        case "/x/v3/fav/resource/batch-deal":
            return DemoFixtures.ok(#"{"prompt":false,"ga_data":null,"toast_msg":""}"#)
        case "/x/v3/fav/folder/add":
            return DemoFixtures.ok(#"{"id":3004,"fid":30,"mid":10001,"attr":2,"title":"新建的收藏夹","fav_state":0,"media_count":0}"#)
        default:
            return nil
        }
    }

    private static let folders = """
    {"count":3,"list":[
      {"id":3001,"fid":1,"mid":10001,"attr":0,"title":"默认收藏夹","fav_state":1,"media_count":128},
      {"id":3002,"fid":2,"mid":10001,"attr":2,"title":"演示：动画","fav_state":0,"media_count":36},
      {"id":3003,"fid":3,"mid":10001,"attr":3,"title":"演示：私密","fav_state":0,"media_count":5}]}
    """
}
#endif
