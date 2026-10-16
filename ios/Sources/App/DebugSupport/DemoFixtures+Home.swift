#if DEBUG
import Foundation

/// Invented answers for 首页's 推荐 feed and the 历史记录 page. Every feed page holds `feedPageSize` videos plus
/// an ad and a live card the app must drop, and repeats the previous page's last video, as the real feed does.
/// History has two pages and then an empty one.
enum HomeFixtures {
    static let feedPageSize = 10
    static let historyPageSizes = [6, 4]
    static let finishedBvid = "BV1Hs4y1H003"

    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch url.path {
        case "/x/web-interface/wbi/index/top/feed/rcmd", "/x/web-interface/index/top/feed/rcmd":
            return DemoFixtures.ok(feed(index: Int(query["fresh_idx"] ?? "") ?? 1))
        case "/x/web-interface/history/cursor":
            return DemoFixtures.ok(history(max: Int64(query["max"] ?? "") ?? 0))
        case "/x/v2/history/toview/add":
            return (200, Data(#"{"code":0,"message":"0","ttl":1}"#.utf8))
        default:
            return nil
        }
    }

    // MARK: 推荐

    static func feedBvid(page: Int, slot: Int) -> String {
        "BV1Fe4y1" + String(format: "%02d%02d", page % 100, slot)
    }

    private static let titles = [
        "猫猫为亚运会加油", "海底捞过生日？这里弟子各有喜怒哀乐", "荣荣猜你左手拿的是手机",
        "超震撼的 8K 视频用于 OLED 显示测试 | 杜比视界演示", "【游戏番剧式】一口气看完的长篇大电影",
        "异世界轻冒险游戏来袭，这次你会选择哪个职业呢？", "【演示】十分钟学会做一碗地道的兰州拉面",
        "当你第一次去大城市上班", "【4K】雨后的山城夜景，太治愈了", "这个开局，谁看了不迷糊",
        "我的猫学会了开门，现在家里没有秘密了", "用三十天时间，从零开始搭一座小木屋",
    ]
    private static let owners = ["为什么是小兔豆_", "小葱派派", "4K杜比视界演示", "游戏大电影", "大宝哥游戏解说", "演示美食家", "山城旅人"]

    private static func feedItem(page: Int, slot: Int) -> String {
        let n = page * 7 + slot * 3
        let bvid = feedBvid(page: page, slot: slot)
        let aid = 800_000_000 + page * 100 + slot
        let vertical = n % 5 == 0
        let reason = n % 4 == 1 ? #"{"content":"\#(n % 3 + 1)万点赞","reason_type":3}"# : "null"
        let (width, height) = vertical ? (1080, 1920) : (1920, 1080)
        return """
        {"id":\(aid),"bvid":"\(bvid)","cid":\(aid + 100_000_000),"goto":"av","uri":"https://www.bilibili.com/video/\(bvid)",
         "pic":"https://example.invalid/demo/feed/\(bvid).jpg","title":"\(titles[n % titles.count])",
         "duration":\([18, 12, 794, 93_723, 315, 1_208, 47][n % 7]),"pubdate":1791600000,
         "owner":{"mid":\(3000 + n % owners.count),"name":"\(owners[n % owners.count])","face":"https://example.invalid/demo/up\(n % owners.count).jpg"},
         "stat":{"view":\([91_000, 8096, 1930, 236_000, 35_000, 947_000, 12_345][n % 7]),"like":\(n * 37),"danmaku":\([6, 2, 0, 519, 32, 405, 77][n % 7])},
         "dimension":{"width":\(width),"height":\(height),"rotate":0},
         "rcmd_reason":\(reason),"is_followed":0,"show_info":1,"track_id":"demo"}
        """
    }

    static func feed(index: Int) -> String {
        var items = (0..<feedPageSize).map { feedItem(page: index, slot: $0) }
        if index > 1 { items.insert(feedItem(page: index - 1, slot: feedPageSize - 1), at: 0) }
        items.insert(#"{"id":0,"bvid":"","cid":0,"goto":"ad","title":"","pic":"","duration":0,"owner":null,"stat":null,"rcmd_reason":null}"#, at: 2)
        items.append(#"{"id":0,"bvid":"","cid":0,"goto":"live","title":"演示直播间","pic":"","duration":0,"owner":{"mid":1,"name":"演示主播","face":""},"stat":null,"room_info":{"room_id":1}}"#)
        return #"{"item":[\#(items.joined(separator: ","))],"side_bar_column":[],"business_card":null,"mid":10001}"#
    }

    // MARK: 历史记录

    private struct Entry {
        let title: String
        let owner: String
        let progress: Int
        let duration: Int
        let device: Int
        /// Seconds before now (今天), or a day count before today with a time of day.
        let age: Age
    }

    private enum Age {
        case minutes(Int)
        case days(Int, hour: Int)
    }

    private static let entries: [Entry] = [
        Entry(title: "关于演示V3的一点小建议和常见问题", owner: "演示下课后", progress: 2, duration: 132, device: 1, age: .minutes(6)),
        Entry(title: "狼来了，真的假的？演示银狼行动绝境篇", owner: "演示君", progress: 1, duration: 149, device: 1, age: .minutes(7)),
        Entry(title: "【演示】这首歌让我循环了一整天", owner: "演示音乐", progress: -1, duration: 195, device: 1, age: .minutes(9)),
        Entry(title: "【4K HDR】《东京上空》极限画质挑战！", owner: "三桂花鱼", progress: 5, duration: 271, device: 2, age: .minutes(48)),
        Entry(title: "最佳16K HDR 120FPS视频 | 杜比视界 | 4K视频/8K超高清电视", owner: "16K视界", progress: 25, duration: 2122, device: 33, age: .days(1, hour: 22)),
        Entry(title: "《梦见未来》4分18秒一口气看完", owner: "演示影视", progress: 98, duration: 258, device: 4, age: .days(1, hour: 9)),
        Entry(title: "用三十天时间，从零开始搭一座小木屋", owner: "山城旅人", progress: 812, duration: 1830, device: 1, age: .days(4, hour: 21)),
        Entry(title: "当你第一次去大城市上班", owner: "演示生活", progress: -1, duration: 345, device: 2, age: .days(4, hour: 12)),
        Entry(title: "十分钟学会做一碗地道的兰州拉面", owner: "演示美食家", progress: 301, duration: 602, device: 1, age: .days(16, hour: 19)),
        Entry(title: "【演示】雨后的山城夜景，太治愈了", owner: "山城旅人", progress: 44, duration: 225, device: 1, age: .days(400, hour: 20)),
    ]

    private static func viewAt(_ age: Age) -> Int64 {
        let now = Date()
        switch age {
        case .minutes(let minutes):
            return Int64(now.timeIntervalSince1970) - Int64(minutes * 60)
        case .days(let days, let hour):
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            return Int64(day.timeIntervalSince1970) + Int64(hour * 3600 + 17 * 60)
        }
    }

    private static func aid(_ index: Int) -> Int64 { 810_000_000 + Int64(index) }

    private static func historyBvid(_ index: Int) -> String {
        "BV1Hs4y1H" + String(format: "%03d", index + 1)
    }

    private static func historyItem(_ index: Int) -> String {
        let entry = entries[index]
        let bvid = historyBvid(index)
        return """
        {"title":"\(entry.title)","long_title":"","cover":"http://example.invalid/demo/history/\(bvid).jpg","covers":null,
         "uri":"","history":{"oid":\(aid(index)),"epid":0,"bvid":"\(bvid)","page":1,"cid":\(aid(index) + 100_000_000),"part":"P1",
                            "business":"archive","dt":\(entry.device)},
         "videos":1,"author_name":"\(entry.owner)","author_face":"https://example.invalid/demo/up.jpg","author_mid":\(4000 + index),
         "view_at":\(viewAt(entry.age)),"progress":\(entry.progress),"badge":"","show_title":"","duration":\(entry.duration),
         "current":"","total":0,"new_desc":"","is_finish":\(entry.progress < 0 ? 1 : 0),"is_fav":0,"kid":\(aid(index)),
         "tag_name":"演示","live_status":0}
        """
    }

    /// `max` is the aid the previous page ended with: 0 asks for the first page.
    static func history(max: Int64) -> String {
        let bounds = historyPageSizes.reduce(into: [0]) { $0.append($0.last! + $1) }
        let page: Range<Int>
        if max == 0 {
            page = bounds[0]..<bounds[1]
        } else if let end = bounds.dropFirst().firstIndex(where: { $0 > 0 && aid($0 - 1) == max }), end + 1 < bounds.count {
            page = bounds[end]..<bounds[end + 1]
        } else {
            return #"{"cursor":{"max":0,"view_at":0,"business":"archive","ps":20},"tab":[],"list":[]}"#
        }
        let last = page.upperBound - 1
        let list = page.map(historyItem).joined(separator: ",")
        return """
        {"cursor":{"max":\(aid(last)),"view_at":\(viewAt(entries[last].age)),"business":"archive","ps":20},
         "tab":[{"type":"archive","name":"视频"}],"list":[\(list)]}
        """
    }
}
#endif
