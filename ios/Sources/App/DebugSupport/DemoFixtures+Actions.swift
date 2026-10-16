#if DEBUG
import Foundation

/// Invented answers for the actions: every write succeeds, 三连 spends two coins, and the actions demo screens open
/// a video this account has already liked, coined and favourited. Coins and folders are in `FavouritesFixtures`.
enum ActionsFixtures {
    static let activeScreen = "page-actions-active"

    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        switch url.path {
        case "/x/web-interface/archive/relation":
            // Listed before the 简介's fixtures, which answer the relation of every other demo screen.
            guard let screen = UserDefaults.standard.string(forKey: "DemoScreen"), ActionsDemo.screens.contains(screen) else { return nil }
            return DemoFixtures.ok(#"{"attention":false,"favorite":true,"season_fav":false,"like":true,"dislike":false,"coin":1}"#)
        case "/x/web-interface/archive/like", "/x/relation/modify":
            return DemoFixtures.ok("null")
        case "/x/web-interface/archive/like/triple":
            return DemoFixtures.ok(#"{"like":true,"coin":true,"fav":true,"multiply":2,"id_list":[3001],"prompt":false}"#)
        case "/x/web-interface/coin/add":
            return DemoFixtures.ok(#"{"like":false}"#)
        case "/x/web-interface/share/add":
            return DemoFixtures.ok("149")
        default:
            return nil
        }
    }
}
#endif
