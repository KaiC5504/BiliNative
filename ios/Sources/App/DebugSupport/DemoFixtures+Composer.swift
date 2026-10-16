#if DEBUG
import Foundation
import UIKit
import BiliAPI

/// The composer's demo answers: an emote panel of invented packages (one large, one 颜文字) drawn locally, and
/// reply/add, which echoes the form back as the demo account's new comment.
enum ComposerFixtures {
    private static let base = "https://example.invalid/demo/emotes"

    private struct Package {
        var id: Int64
        var name: String
        var icon: String
        var type = 1
        var large = false
        var emotes: [(token: String, art: String)]
    }

    /// The art names are emoji, drawn by `image(for:)`; a large package's are drawn on a tile.
    private static let packages: [Package] = [
        Package(id: 1, name: "小黄脸", icon: "🐶", emotes: [
            ("[doge]", "🐶"), ("[微笑]", "🙂"), ("[OK]", "👌"), ("[星星眼]", "🤩"), ("[妙啊]", "😮"), ("[辣眼睛]", "🙈"),
            ("[吃瓜]", "🍉"), ("[滑稽]", "😏"), ("[呲牙]", "😁"), ("[打call]", "📣"), ("[歪嘴]", "😼"), ("[调皮]", "😜"),
            ("[嗑瓜子]", "🌻"), ("[笑哭]", "😂"), ("[脱单doge]", "🐕"), ("[给心心]", "🫶"), ("[嘟嘟]", "😗"), ("[哦呼]", "😯"),
            ("[喜欢]", "😍"), ("[酸了]", "🍋"), ("[嫌弃]", "😒"), ("[大哭]", "😭"), ("[害羞]", "☺️"), ("[疑惑]", "🤔"),
            ("[喜极而泣]", "🥲"), ("[奸笑]", "😈"), ("[笑]", "😄"), ("[偷笑]", "🤭"),
        ]),
        Package(id: 2, name: "热词系列", icon: "💬", large: true, emotes: [
            ("[热词系列_好耶]", "🎉"), ("[热词系列_泪目]", "🥹"), ("[热词系列_破防了]", "💔"), ("[热词系列_爷青回]", "🌱"),
            ("[热词系列_知识增加]", "📚"), ("[热词系列_三连]", "👍"), ("[热词系列_awsl]", "💖"), ("[热词系列_奥力给]", "💪"),
        ]),
        Package(id: 3, name: "小电视", icon: "📺", emotes: [
            ("[tv_白眼]", "🙄"), ("[tv_doge]", "📺"), ("[tv_坏笑]", "😏"), ("[tv_难过]", "😢"), ("[tv_生气]", "😠"),
            ("[tv_惊讶]", "😲"), ("[tv_呆]", "😐"), ("[tv_鼓掌]", "👏"), ("[tv_晕]", "😵"), ("[tv_思考]", "🧐"),
            ("[tv_点赞]", "👍"), ("[tv_调皮]", "😝"), ("[tv_睡着]", "😴"), ("[tv_爱心]", "❤️"),
        ]),
        Package(id: 4, name: "颜文字", icon: "", type: 4, emotes: [
            ("(⌒▽⌒)", ""), ("（￣▽￣）", ""), ("(=・ω・=)", ""), ("(｀・ω・´)", ""), ("(〜￣△￣)〜", ""), ("(･∀･)", ""),
            ("(°∀°)ﾉ", ""), ("(￣3￣)", ""), ("╮(￣▽￣)╭", ""), ("( ´_ゝ｀)", ""), ("←_←", ""), ("→_→", ""),
            ("(<_<)", ""), ("(>_>)", ""), ("(;¬_¬)", ""),
        ]),
        Package(id: 5, name: "2233娘", icon: "👧", emotes: [
            ("[2233娘_大笑]", "😆"), ("[2233娘_吃惊]", "😳"), ("[2233娘_卖萌]", "🥰"), ("[2233娘_无言]", "😶"),
            ("[2233娘_喝水]", "🥤"), ("[2233娘_耶]", "✌️"), ("[2233娘_委屈]", "🥺"),
        ]),
    ]

    /// What the composer demo has used before, so 最近使用 is not empty in the screenshot.
    static let recent = Emote(token: "[吃瓜]", url: url(for: "🍉"), large: false)

    static func handle(_ url: URL, _ method: String) -> (Int, Data)? {
        guard url.path == "/x/emote/user/panel/web" else { return nil }
        return DemoFixtures.ok(#"{"setting":{"recent_limit":14},"packages":[\#(packages.map(json).joined(separator: ","))]}"#)
    }

    /// reply/add needs the form, which `handle` does not see; `DemoTransport` asks here first.
    static func post(_ request: HTTPRequest) -> (Int, Data)? {
        guard request.url.path == "/x/v2/reply/add" else { return nil }
        var form: [String: String] = [:]
        for pair in String(decoding: request.body ?? Data(), as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if let name = parts.first?.removingPercentEncoding {
                form[name] = parts.count > 1 ? parts[1].removingPercentEncoding ?? "" : ""
            }
        }
        let message = form["message"] ?? ""
        let rpid = 700_000_000 + Int64(Date().timeIntervalSince1970 * 10) % 100_000_000
        let emotes = packages.filter { $0.type != 4 }.flatMap { package in package.emotes.map { (package, $0) } }
            .filter { message.contains($0.1.token) }
            .map { package, emote in
                "\(string(emote.token)):{\"url\":\"\(url(for: emote.art, large: package.large))\",\"meta\":{\"size\":\(package.large ? 2 : 1)}}"
            }
        let comment = """
        {"rpid":\(rpid),"oid":\(form["oid"] ?? "0"),"type":1,"mid":\(CommentFixtures.ownMid),"root":\(form["root"] ?? "0"),
         "parent":\(form["parent"] ?? "0"),"count":0,"rcount":0,"ctime":\(Int64(Date().timeIntervalSince1970)),"like":0,"action":0,
         "member":{"mid":"\(CommentFixtures.ownMid)","uname":"演示用户","avatar":"https://example.invalid/demo/face/\(CommentFixtures.ownMid).jpg",
                   "level_info":{"current_level":4},"vip":{"vipType":2,"vipStatus":1}},
         "content":{"message":\(string(message)),"emote":{\(emotes.joined(separator: ","))}},
         "replies":null,"up_action":{"like":false,"reply":false},"reply_control":{"location":"IP属地：广东"}}
        """
        return DemoFixtures.ok(#"{"rpid":\#(rpid),"success_toast":"发送成功","reply":\#(comment)}"#)
    }

    private static func json(_ package: Package) -> String {
        let emotes = package.emotes.enumerated().map { index, emote in
            let address = emote.art.isEmpty ? "" : url(for: emote.art, large: package.large)
            return #"{"id":\#(package.id * 1000 + Int64(index)),"package_id":\#(package.id),"text":\#(string(emote.token)),"url":"\#(address)","meta":{"size":\#(package.large ? 2 : 1)},"type":\#(package.type)}"#
        }
        let icon = package.icon.isEmpty ? "" : url(for: package.icon)
        return #"{"id":\#(package.id),"text":\#(string(package.name)),"url":"\#(icon)","type":\#(package.type),"emote":[\#(emotes.joined(separator: ","))]}"#
    }

    private static func string(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: text, options: .fragmentsAllowed)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// The emoji travels in the address, hex-encoded, so the image needs no table of its own.
    private static func url(for art: String, large: Bool = false) -> String {
        let hex = art.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        return "\(base)/\(large ? "large" : "small")/\(hex).png"
    }

    /// Art for the panel's addresses; nil for any other.
    static func image(for url: URL) -> Data? {
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[0] == "demo", parts[1] == "emotes" else { return nil }
        let scalars = parts[3].split(separator: ".").first?.split(separator: "-").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) } ?? []
        var glyph = ""
        glyph.unicodeScalars.append(contentsOf: scalars)
        let large = parts[2] == "large"
        let side: CGFloat = large ? 96 : 40
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
            if large {
                UIColor(red: 1, green: 0.93, blue: 0.85, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 4, y: 4, width: side - 8, height: side - 8), cornerRadius: 16).fill()
            }
            let size = large ? side * 0.55 : side * 0.8
            let text = NSAttributedString(string: glyph, attributes: [.font: UIFont.systemFont(ofSize: size)])
            let bounds = text.size()
            text.draw(at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2))
        }
    }
}
#endif
