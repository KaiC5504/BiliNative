#if DEBUG
import Foundation
import UIKit

/// Canned Bilibili replies with invented data, used when the app is launched with `-DemoData YES`.
enum DemoFixtures {
    typealias Handler = (_ url: URL, _ method: String) -> (Int, Data)?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "DemoData") }

    /// Tried in order; a task that adds an endpoint adds a handler in its own file and lists it here.
    static let handlers: [Handler] = [DemoFixtures.launch, VideoPageFixtures.handle, DanmakuFixtures.handle, DemoFixtures.danmakuPost, DemoFixtures.blockRules,
                                       HomeFixtures.handle, IntroFixtures.handle, CommentFixtures.handle]

    static func response(for url: URL, method: String) -> (Int, Data) {
        for handler in handlers {
            if let found = handler(url, method) { return found }
        }
        return (404, Data(#"{"code":-404,"message":"演示数据里没有这个接口","ttl":1}"#.utf8))
    }

    /// A code 0 envelope around `data`, which is already JSON.
    static func ok(_ data: String) -> (Int, Data) {
        (200, Data(#"{"code":0,"message":"0","ttl":1,"data":\#(data)}"#.utf8))
    }

    /// What the app asks for on every launch: the risk cookies and the account check. The wbi keys
    /// only need to look right, since nothing here verifies a signature.
    static func launch(_ url: URL, _ method: String) -> (Int, Data)? {
        switch url.path {
        case "/x/frontend/finger/spi":
            return ok(#"{"b_3":"DEMO0000-0000-0000-0000-000000000000infoc","b_4":"DEMO0000-0000-0000-0000-000000000000-00000000-demo"}"#)
        case "/x/web-interface/nav":
            return ok("""
            {"isLogin":true,"mid":10001,"uname":"演示用户","face":"https://example.invalid/demo/me.jpg","vipStatus":1,"vipType":2,
             "wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/0123456789abcdef0123456789abcdef.png",
                        "sub_url":"https://i0.hdslb.com/bfs/wbi/fedcba9876543210fedcba9876543210.png"}}
            """)
        default:
            return nil
        }
    }

    /// A flat-gradient PNG whose colour comes from the URL, so covers and avatars differ without a network.
    static func image(for url: URL) async throws -> Data {
        if let art = CommentFixtures.image(for: url) { return art }
        var hash: UInt32 = 5381
        for byte in url.absoluteString.utf8 { hash = hash &* 33 &+ UInt32(byte) }
        let hue = CGFloat(hash % 360) / 360
        let top = UIColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1)
        let bottom = UIColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.75, alpha: 1)
        let size = CGSize(width: 160, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray,
                                            locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}
#endif
