#if DEBUG
import Foundation

/// Invented answers for the 简介: the uploader card, the relation, the tags and the related videos.
enum IntroFixtures {
    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        switch url.path {
        case "/x/web-interface/card":
            return DemoFixtures.ok(card)
        case "/x/web-interface/archive/relation":
            return DemoFixtures.ok(#"{"attention":false,"favorite":false,"season_fav":false,"like":false,"dislike":false,"coin":0}"#)
        case "/x/web-interface/view/detail/tag":
            return DemoFixtures.ok(tags)
        case "/x/web-interface/archive/related":
            return DemoFixtures.ok(related)
        default:
            return nil
        }
    }

    private static let face = "https://example.invalid/demo/face.jpg"

    private static let card = """
    {"card":{"mid":"42","name":"演示UP主","approve":false,"sex":"保密","face":"\(face)","fans":475000,"attention":36,
             "sign":"演示用的签名","level_info":{"current_level":6},
             "vip":{"type":2,"status":1,"due_date":4102444800000,"vipType":2,"vipStatus":1}},
     "following":false,"archive_count":410,"article_count":0,"follower":475000,"like_num":1200000}
    """

    private static let tags = """
    [{"tag_id":0,"tag_name":"演示BGM - 演示歌手","music_id":"MA0000000001","tag_type":"bgm","jump_url":"https://example.invalid/bgm/1"},
     {"tag_id":3001,"tag_name":"演示话题激励计划","music_id":"","tag_type":"topic","jump_url":"https://example.invalid/topic/1"},
     {"tag_id":2001,"tag_name":"必剪创作","music_id":"","tag_type":"old_channel","jump_url":""},
     {"tag_id":2002,"tag_name":"演示标签","music_id":"","tag_type":"old_channel","jump_url":""}]
    """

    private static func card(_ index: Int, title: String, owner: String, views: Int, danmaku: Int, duration: Int,
                             extra: String = "") -> String {
        let aid = 900_000_010 + index
        let cid = 700_001_001 + index * 100
        let bvid = "BV1Dm4y1R\(index)\(["aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh", "ii"][index - 1])"
        return """
        {"aid":\(aid),"bvid":"\(bvid)","cid":\(cid),"title":"\(title)","pic":"https://example.invalid/demo/related-\(index).jpg",
         "duration":\(duration),"pubdate":1791600000,"owner":{"mid":\(70 + index),"name":"\(owner)","face":"\(face)"},
         "stat":{"aid":\(aid),"view":\(views),"danmaku":\(danmaku),"reply":88,"favorite":900,"coin":300,"share":20,"like":41000}\(extra)}
        """
    }

    /// The first two are the ones the end screens show; the third is a bangumi card the client drops.
    private static var related: String {
        "[" + [
            card(1, title: "【演示】推荐视频一：有被治愈到！", owner: "演示推荐", views: 4_815_000, danmaku: 1700, duration: 155),
            card(2, title: "【演示】推荐视频二：少年，你也喜欢怀念过去吗？", owner: "演示学姐", views: 690_300, danmaku: 1700, duration: 155),
            card(3, title: "【演示】跳转到番剧的条目", owner: "演示番剧", views: 12_000, danmaku: 30, duration: 1420,
                 extra: #","redirect_url":"https://example.invalid/bangumi/play/ep1""#),
            card(4, title: "【演示】可惜我相貌平平，惊艳不了你的青春", owner: "演示学姐", views: 6_903_000, danmaku: 4139, duration: 154),
            card(5, title: "【演示】三分钟看完这一季的全部名场面", owner: "演示剪辑", views: 981, danmaku: 0, duration: 30),
            card(6, title: "【演示】这一段的配乐到底是什么？评论区告诉你", owner: "演示音乐", views: 2018, danmaku: 12, duration: 12),
            card(7, title: "【演示】合集幕后：我们是怎么做出这一集的", owner: "演示UP主", views: 25_000, danmaku: 410, duration: 612),
            card(8, title: "【演示】第一次看就哭了，后劲太大", owner: "演示观众", views: 132_000, danmaku: 2210, duration: 245),
            card(9, title: "【演示】一口气看完：从出发到归来", owner: "演示剪辑", views: 58_000, danmaku: 960, duration: 3725),
        ].joined(separator: ",") + "]"
    }
}
#endif
