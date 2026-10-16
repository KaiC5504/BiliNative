#if DEBUG
import Foundation
import UIKit

/// Invented comments for the demo video: a pinned one by the uploader, 大会员 with pendants and fan cards, emotes,
/// a mention, a link, timestamps, one picture and three, one of the demo account's own, and a thread of replies.
/// Times are relative to now, so the list reads "1小时前" whenever it is photographed.
enum CommentFixtures {
    static let threadRoot: Int64 = 600_003
    static let ownComment: Int64 = 600_004
    static let ownMid: Int64 = 10001
    private static let secondPage = "DEMO_PAGE_2"
    private static let base = "https://example.invalid/demo"

    /// A `DemoFixtures` handler: nil for paths this file does not answer.
    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch url.path {
        case "/x/v2/reply/wbi/main", "/x/v2/reply/main":
            if query["pagination_str"]?.contains(secondPage) == true { return DemoFixtures.ok(laterPage) }
            return DemoFixtures.ok(firstPage(byTime: query["mode"] == "2"))
        case "/x/v2/reply/reply":
            return DemoFixtures.ok(thread(sortedByHot: query["sort"] == "1"))
        case "/x/v2/reply/action", "/x/v2/reply/hate", "/x/v2/reply/del":
            return (200, Data(#"{"code":0,"message":"0","ttl":1}"#.utf8))
        default:
            return nil
        }
    }

    // MARK: members

    private static func member(_ mid: Int64, _ name: String, level: Int, vip: Bool = false, pendant: String? = nil,
                               card: (art: String, number: String, color: String)? = nil) -> String {
        let pendantJSON = pendant.map { #"{"pid":1,"name":"挂件","image":"\#(base)/pendant/\#($0).png"}"# }
            ?? #"{"pid":0,"name":"","image":""}"#
        let cardJSON = card.map {
            #"{"cardbg":{"id":1,"name":"装扮","image":"\#(base)/fancard/\#($0.art).png","fan":{"is_fan":1,"number":1,"color":"\#($0.color)","num_desc":"\#($0.number)"}}}"#
        } ?? "null"
        return """
        {"mid":"\(mid)","uname":"\(name)","avatar":"\(base)/face/\(mid).jpg","level_info":{"current_level":\(level)},
         "pendant":\(pendantJSON),"vip":{"vipType":\(vip ? 2 : 0),"vipStatus":\(vip ? 1 : 0)},"user_sailing":\(cardJSON)}
        """
    }

    private static let up = member(42, "演示UP主", level: 6, vip: true)
    private static let lan = member(2001, "蓝色星期三", level: 6, vip: true, pendant: "snow", card: ("crest", "017949", "#998245"))
    private static let fish = member(2002, "小鱼干", level: 5, card: ("sun", "000015", "#d9a441"))
    private static let me = member(ownMid, "演示用户", level: 4, vip: true)
    private static let tea = member(2003, "清茶一杯", level: 3)
    private static let wind = member(2004, "风吹麦浪", level: 2)
    private static let moon = member(2005, "月半弯", level: 6, vip: true, pendant: "star")

    // MARK: comments

    private static let emotes: [String: (name: String, size: Int)] = [
        "[doge]": ("doge", 1), "[笑哭]": ("laugh", 1), "[星星眼]": ("stars", 1), "[吃瓜]": ("melon", 1),
        "[打call]": ("call", 1), "[喜欢]": ("love", 1),
    ]

    private struct Draft {
        var rpid: Int64
        var mid: Int64
        var member: String
        var message: String
        var minutesAgo: Int64
        var likes = 0
        var replyCount = 0
        var root: Int64 = 0
        var location = "湖北"
        var mentions: [String: Int64] = [:]
        var links: [(key: String, title: String, url: String)] = []
        var pictures: [(width: Int, height: Int)] = []
        var previews: [String] = []
        var upLiked = false
        var action = 0
    }

    private static func json(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func render(_ draft: Draft) -> String {
        let now = Int64(Date().timeIntervalSince1970)
        let used = emotes.filter { draft.message.contains($0.key) }
        let emoteJSON = used.map { token, emote in
            "\(json(token)):{\"url\":\"\(base)/emote/\(emote.name).png\",\"meta\":{\"size\":\(emote.size)}}"
        }.joined(separator: ",")
        let mentionJSON = draft.mentions.map { "\(json($0.key)):\($0.value)" }.joined(separator: ",")
        let linkJSON = draft.links.map { "\(json($0.key)):{\"title\":\(json($0.title)),\"pc_url\":\(json($0.url))}" }.joined(separator: ",")
        let pictureJSON = draft.pictures.enumerated().map { index, size in
            #"{"img_src":"\#(base)/picture/\#(draft.rpid)-\#(index).jpg","img_width":\#(size.width),"img_height":\#(size.height)}"#
        }.joined(separator: ",")
        return """
        {"rpid":\(draft.rpid),"oid":\(VideoPageFixtures.aidA),"type":1,"mid":\(draft.mid),"root":\(draft.root),"parent":\(draft.root),
         "count":\(draft.replyCount),"rcount":\(draft.replyCount),"ctime":\(now - draft.minutesAgo * 60),"like":\(draft.likes),
         "action":\(draft.action),"member":\(draft.member),
         "content":{"message":\(json(draft.message)),"emote":{\(emoteJSON)},"at_name_to_mid":{\(mentionJSON)},
                    "jump_url":{\(linkJSON)},"pictures":[\(pictureJSON)]},
         "replies":[\(draft.previews.joined(separator: ","))],"up_action":{"like":\(draft.upLiked),"reply":false},
         "reply_control":{"location":"IP属地：\(draft.location)"}}
        """
    }

    private static var pinned: String {
        render(Draft(rpid: 600_001, mid: 42, member: up,
                     message: "这期的幕后花絮在 02:15，下一集在这里 \(VideoPageFixtures.bvidB) ，大家多多讨论[doge]",
                     minutesAgo: 300, likes: 2381, replyCount: 46, location: "上海", upLiked: false))
    }

    private static func previewReply(_ rpid: Int64, root: Int64, member: String, mid: Int64, message: String, likes: Int) -> String {
        render(Draft(rpid: rpid, mid: mid, member: member, message: message, minutesAgo: 50, likes: likes, root: root))
    }

    private static var picture: String {
        render(Draft(rpid: 600_002, mid: 2001, member: lan, message: "出发那天随手拍的，光线刚刚好[星星眼]", minutesAgo: 62,
                     likes: 60, replyCount: 12, pictures: [(1080, 1600)]))
    }

    private static var threaded: String {
        render(Draft(rpid: threadRoot, mid: 2002, member: fish,
                     message: "我说白了，这一集的节奏比上一集好太多了。开头那段铺垫看似平淡，其实每个镜头都在为结尾埋伏笔，二刷才看出来[笑哭]",
                     minutesAgo: 185, likes: 436, replyCount: 28, location: "河南",
                     previews: [previewReply(600_101, root: threadRoot, member: tea, mid: 2003,
                                             message: "但是结尾那个反转如果不提前看过预告的话，第一遍真的很难猜到，这才是这一集最妙的地方吧", likes: 51)],
                     upLiked: true))
    }

    private static var own: String {
        render(Draft(rpid: ownComment, mid: ownMid, member: me, message: "这是演示账号自己的评论，点 ⋮ 可以删除。三张图：",
                     minutesAgo: 20, likes: 3, location: "广东", pictures: [(1200, 900), (900, 1200), (1000, 1000)], action: 1))
    }

    private static var mention: String {
        render(Draft(rpid: 600_005, mid: 2003, member: tea, message: "@小鱼干 同感！顺便推荐一下拍摄教程，看完收获很多[打call]",
                     minutesAgo: 240, likes: 87, replyCount: 2, location: "四川", mentions: ["小鱼干": 2002],
                     links: [("拍摄教程", "拍摄教程", "//search.bilibili.com/all?keyword=demo")],
                     previews: [previewReply(600_102, root: 600_005, member: wind, mid: 2004, message: "回复 @清茶一杯 :求链接[吃瓜]", likes: 0),
                                previewReply(600_103, root: 600_005, member: moon, mid: 2005, message: "已收藏，谢谢分享", likes: 5)]))
    }

    private static var plain: [String] {
        [
            render(Draft(rpid: 600_006, mid: 2004, member: wind, message: "前排[吃瓜]", minutesAgo: 30, likes: 12, location: "重庆")),
            render(Draft(rpid: 600_007, mid: 2005, member: moon, message: "BGM 是什么？好好听[喜欢]", minutesAgo: 90, likes: 9, location: "北京")),
        ]
    }

    private static func firstPage(byTime: Bool) -> String {
        let replies = byTime ? [own] + plain + [picture, threaded, mention] : [picture, threaded, own, mention] + plain
        return """
        {"cursor":{"is_begin":true,"is_end":false,"mode":\(byTime ? 2 : 3),"all_count":242,
                   "pagination_reply":{"next_offset":"\(secondPage)"}},
         "replies":[\(replies.joined(separator: ","))],"top_replies":[\(pinned)]}
        """
    }

    private static var laterPage: String {
        let later = (0..<3).map { index in
            render(Draft(rpid: 600_200 + Int64(index), mid: 2003, member: tea, message: "第\(index + 8)条演示评论", minutesAgo: 600 + Int64(index) * 30,
                         likes: 3 - index, location: "浙江"))
        }
        return #"{"cursor":{"is_end":true,"all_count":242},"replies":[\#(later.joined(separator: ","))],"top_replies":[]}"#
    }

    private static func thread(sortedByHot: Bool) -> String {
        var replies = [
            render(Draft(rpid: 600_101, mid: 2003, member: tea, message: "但是结尾那个反转如果不提前看过预告的话，第一遍真的很难猜到，这才是这一集最妙的地方吧",
                         minutesAgo: 50, likes: 51, root: threadRoot, location: "重庆")),
            render(Draft(rpid: 600_104, mid: 2005, member: moon, message: "回复 @清茶一杯 :同意，二刷的时候注意 01:30 那个镜头[星星眼]",
                         minutesAgo: 45, likes: 46, root: threadRoot, location: "四川", mentions: ["清茶一杯": 2003])),
            render(Draft(rpid: 600_105, mid: 2001, member: lan, message: "伏笔真的埋得很深", minutesAgo: 40, likes: 3, root: threadRoot,
                         location: "湖北")),
            // The server sometimes sends no mid for the name being answered; it still shows blue.
            render(Draft(rpid: 600_106, mid: 2004, member: wind, message: "回复 @蓝色星期三 :确实，而且配乐也是[打call]", minutesAgo: 35, likes: 0,
                         root: threadRoot, location: "广西")),
        ]
        if sortedByHot { replies.reverse() }
        return """
        {"page":{"num":1,"size":20,"count":28,"acount":28},"root":\(threaded),"replies":[\(replies.joined(separator: ","))]}
        """
    }

    // MARK: images

    /// Art for the comment fixtures' image addresses: emotes as emoji, pendants as rings, fan cards as a badge with room
    /// for the number, pictures as gradients at their own shape. Nil for any other address.
    static func image(for url: URL) -> Data? {
        let parts = url.path.split(separator: "/")
        guard parts.count >= 3, parts[0] == "demo" else { return nil }
        let name = String(parts[2].split(separator: ".").first ?? "")
        switch parts[1] {
        case "emote": return emote(name)
        case "pendant": return pendant(name)
        case "fancard": return fanCard(name)
        default: return nil
        }
    }

    private static func render(size: CGSize, _ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).pngData { draw($0.cgContext) }
    }

    private static func emote(_ name: String) -> Data {
        let glyph = ["doge": "🐶", "laugh": "😂", "stars": "🤩", "melon": "🍉", "call": "📣", "love": "😍"][name] ?? "🙂"
        return render(size: CGSize(width: 40, height: 40)) { _ in
            NSAttributedString(string: glyph, attributes: [.font: UIFont.systemFont(ofSize: 32)]).draw(at: CGPoint(x: 1, y: 0))
        }
    }

    private static func pendant(_ name: String) -> Data {
        let colour = name == "snow" ? UIColor(red: 0.62, green: 0.68, blue: 0.95, alpha: 1) : UIColor(red: 0.98, green: 0.72, blue: 0.3, alpha: 1)
        return render(size: CGSize(width: 96, height: 96)) { context in
            colour.setStroke()
            context.setLineWidth(5)
            context.strokeEllipse(in: CGRect(x: 21, y: 21, width: 54, height: 54))
            colour.setFill()
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3 - .pi / 2
                let centre = CGPoint(x: 48 + cos(angle) * 34, y: 48 + sin(angle) * 34)
                context.fillEllipse(in: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12))
            }
        }
    }

    private static func fanCard(_ name: String) -> Data {
        let colour = name == "crest" ? UIColor(red: 0.27, green: 0.45, blue: 0.75, alpha: 1) : UIColor(red: 0.85, green: 0.64, blue: 0.25, alpha: 1)
        return render(size: CGSize(width: 120, height: 60)) { context in
            colour.setFill()
            context.fillEllipse(in: CGRect(x: 4, y: 4, width: 52, height: 52))
            UIColor.white.setFill()
            context.fillEllipse(in: CGRect(x: 14, y: 14, width: 32, height: 32))
            colour.setFill()
            context.fillEllipse(in: CGRect(x: 22, y: 22, width: 16, height: 16))
        }
    }
}
#endif
