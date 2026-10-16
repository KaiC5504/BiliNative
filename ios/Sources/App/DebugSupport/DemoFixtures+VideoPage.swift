#if DEBUG
import Foundation

/// Invented answers for the video page's endpoints. Video A has two parts and opens a 合集 of two
/// sections, A and B in the first and C in the second, so autoplay can walk it.
enum VideoPageFixtures {
    static let bvidA = "BV1Dm4y1A7aa"
    static let bvidB = "BV1Dm4y1A7bb"
    static let bvidC = "BV1Dm4y1A7cc"
    static let aidA: Int64 = 900_000_001
    static let aidB: Int64 = 900_000_002
    static let aidC: Int64 = 900_000_003
    static let cidA1: Int64 = 700_000_101
    static let cidA2: Int64 = 700_000_102
    static let cidB: Int64 = 700_000_201
    static let cidC: Int64 = 700_000_301
    /// What player/wbi/v2 names as the part last played, for a route without a cid.
    static let lastPlayCid = cidA2

    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch url.path {
        case "/x/web-interface/wbi/view", "/x/web-interface/view":
            return DemoFixtures.ok(view(bvid: query["bvid"] ?? bvidA))
        case "/x/player/wbi/v2", "/x/player/v2":
            return DemoFixtures.ok(playerV2)
        case "/x/web-interface/archive/related":
            return DemoFixtures.ok(related)
        case "/x/player/online/total":
            return DemoFixtures.ok(#"{"total":"53","count":"41","show_switch":{"total":true,"count":true}}"#)
        case "/x/click-interface/web/heartbeat":
            return (200, Data(#"{"code":0,"message":"0","ttl":1}"#.utf8))
        case "/x/player/wbi/playurl", "/x/player/playurl":
            return DemoFixtures.ok(playURL(cid: Int64(query["cid"] ?? "") ?? cidA1))
        default:
            return nil
        }
    }

    private static let cover = "https://example.invalid/demo/cover.jpg"
    private static let face = "https://example.invalid/demo/face.jpg"

    private static func episode(aid: Int64, bvid: String, cid: Int64, title: String, views: Int, pubdate: Int) -> String {
        """
        {"season_id":5001,"section_id":6001,"id":\(aid),"aid":\(aid),"cid":\(cid),"title":"\(title)","attribute":0,"bvid":"\(bvid)",
         "arc":{"aid":\(aid),"pic":"\(cover)","title":"\(title)","pubdate":\(pubdate),"ctime":\(pubdate),"duration":200,
                "stat":{"aid":\(aid),"view":\(views),"danmaku":120,"reply":30,"fav":40,"coin":12,"share":3,"like":900}},
         "page":{"cid":\(cid),"page":1,"part":"\(title)","duration":200}}
        """
    }

    private static var season: String {
        """
        {"id":5001,"title":"演示合集","cover":"\(cover)","mid":42,"intro":"演示用的合集，两个小节。","sign_state":0,"attribute":140,
         "sections":[
          {"season_id":5001,"id":6001,"title":"第一季","type":1,"episodes":[
            \(episode(aid: aidA, bvid: bvidA, cid: cidA1, title: "第一集：出发", views: 37000, pubdate: 1_791_700_000)),
            \(episode(aid: aidB, bvid: bvidB, cid: cidB, title: "第二集：途中", views: 21000, pubdate: 1_791_800_000))]},
          {"season_id":5001,"id":6002,"title":"第二季","type":1,"episodes":[
            \(episode(aid: aidC, bvid: bvidC, cid: cidC, title: "第三集：归来", views: 9800, pubdate: 1_791_900_000))]}],
         "stat":{"season_id":5001,"view":67800,"danmaku":360},"ep_count":3,"season_type":1}
        """
    }

    private static func page(cid: Int64, number: Int, part: String, duration: Int) -> String {
        #"{"cid":\#(cid),"page":\#(number),"from":"vupload","part":"\#(part)","duration":\#(duration),"vid":"","weblink":"","dimension":{"width":1920,"height":1080,"rotate":0}}"#
    }

    private static func entry(_ bvid: String) -> (aid: Int64, cid: Int64, title: String, pages: [String]) {
        switch bvid {
        case bvidB:
            return (aidB, cidB, "【演示】第二集：途中", [page(cid: cidB, number: 1, part: "第二集", duration: 200)])
        case bvidC:
            return (aidC, cidC, "【演示】第三集：归来", [page(cid: cidC, number: 1, part: "第三集", duration: 200)])
        default:
            return (aidA, cidA1, "【演示】第一集：出发，终于等到这一天！",
                    [page(cid: cidA1, number: 1, part: "上篇", duration: 200), page(cid: cidA2, number: 2, part: "下篇", duration: 180)])
        }
    }

    static func view(bvid: String) -> String {
        let (aid, cid, title, pages) = entry(bvid)
        return """
        {"bvid":"\(bvid)","aid":\(aid),"videos":\(pages.count),"tid":24,"tname":"动画","copyright":1,"pic":"\(cover)",
         "title":"\(title)","pubdate":1791700000,"ctime":1791700000,"desc":"演示视频的简介。","duration":200,
         "desc_v2":[{"raw_text":"演示视频的简介，","type":1,"biz_id":0},{"raw_text":"演示UP主","type":2,"biz_id":42}],
         "rights":{"bp":0,"elec":0,"download":1,"movie":0,"pay":0,"hd5":1,"no_reprint":1,"autoplay":1,"ugc_pay":0},
         "owner":{"mid":42,"name":"演示UP主","face":"\(face)"},
         "stat":{"aid":\(aid),"view":37000,"danmaku":337,"reply":213,"favorite":3907,"coin":1210,"share":148,"now_rank":0,
                 "his_rank":0,"like":9131,"dislike":0},
         "dynamic":"","cid":\(cid),
         "dimension":{"width":1920,"height":1080,"rotate":0},
         "pages":[\(pages.joined(separator: ","))],
         "ugc_season":\(season),
         "honor_reply":{"honor":[{"aid":\(aid),"type":7,"desc":"活动","weekly_recommend_num":0}]}}
        """
    }

    private static let playerV2 = """
    {"aid":\(aidA),"bvid":"\(bvidA)","cid":\(cidA1),"last_play_time":65000,"last_play_cid":\(lastPlayCid),
     "view_points":[{"type":2,"from":0,"to":60,"content":"开场","imgUrl":""},
                    {"type":2,"from":60,"to":140,"content":"正片","imgUrl":""},
                    {"type":2,"from":140,"to":200,"content":"彩蛋","imgUrl":""}]}
    """

    private static func card(aid: Int64, bvid: String, cid: Int64, title: String, owner: String, views: Int, extra: String = "") -> String {
        """
        {"aid":\(aid),"bvid":"\(bvid)","cid":\(cid),"title":"\(title)","pic":"\(cover)","duration":155,"pubdate":1791600000,
         "owner":{"mid":77,"name":"\(owner)","face":"\(face)"},
         "stat":{"aid":\(aid),"view":\(views),"danmaku":1700,"reply":88,"favorite":900,"coin":300,"share":20,"like":41000}\(extra)}
        """
    }

    private static var related: String {
        "[" + [
            card(aid: 900_000_011, bvid: "BV1Dm4y1R1aa", cid: 700_001_101, title: "【演示】推荐视频一：有被治愈到！", owner: "演示推荐", views: 4_815_000),
            card(aid: 900_000_012, bvid: "BV1Dm4y1R2bb", cid: 700_001_201, title: "【演示】推荐视频二：少年，你也喜欢怀念过去吗？", owner: "演示学姐", views: 690_300),
            card(aid: 900_000_013, bvid: "BV1Dm4y1R3cc", cid: 700_001_301, title: "【演示】跳转到番剧的条目", owner: "演示番剧", views: 12_000,
                 extra: #","redirect_url":"https://example.invalid/bangumi/play/ep1""#),
        ].joined(separator: ",") + "]"
    }

    private static func playURL(cid: Int64) -> String {
        func stream(_ id: Int, _ codecs: String, _ codecid: Int, _ width: Int, _ height: Int) -> String {
            """
            {"id":\(id),"baseUrl":"https://example.invalid/upgcxcode/\(cid)-\(id).m4s?deadline=4102444800","backupUrl":[],
             "bandwidth":1500000,"mimeType":"video/mp4","codecs":"\(codecs)","width":\(width),"height":\(height),"frameRate":"30",
             "codecid":\(codecid),"SegmentBase":{"Initialization":"0-999","indexRange":"1000-1999"}}
            """
        }
        return """
        {"quality":80,"format":"flv","timelength":200000,"accept_format":"hdflv2,flv,flv720,flv480","video_codecid":12,
         "accept_description":["超清 4K","高清 1080P","高清 720P"],"accept_quality":[120,80,64],
         "last_play_time":65000,"last_play_cid":\(cidA1),
         "dash":{"duration":200,"minBufferTime":1.5,
           "video":[\(stream(80, "hev1.1.6.L120.90", 12, 1920, 1080)),\(stream(80, "avc1.640032", 7, 1920, 1080))],
           "audio":[{"id":30280,"baseUrl":"https://example.invalid/upgcxcode/\(cid)-30280.m4s?deadline=4102444800","backupUrl":[],
                     "bandwidth":192000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","codecid":0,
                     "SegmentBase":{"Initialization":"0-799","indexRange":"800-1499"}}]}}
        """
    }
}
#endif
