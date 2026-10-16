import SwiftUI
import UIKit
import XCTest
import BiliAPI
@testable import BiliNative

@MainActor
final class DanmakuSendTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private let postPath = "/x/v2/dm/post"

    func testSendPostsTheDraftAndShowsItAtOnce() async throws {
        let rig = try await makeRig(position: 61.5)
        rig.sender.style = DanmakuStyle(fontSize: 18, mode: 5, color: 0xD42D25, gradient: false)
        rig.sender.text = "你好"
        _ = rig.danmaku.pendingItems(atMs: 61_500)
        let failure = await rig.sender.send()
        XCTAssertNil(failure)
        let posts = rig.http.requests(to: postPath)
        XCTAssertEqual(posts.count, 1)
        let body = String(decoding: posts.first?.body ?? Data(), as: UTF8.self)
        for field in ["type=1", "oid=\(F.cidA1)", "bvid=\(F.bvidA)", "msg=%E4%BD%A0%E5%A5%BD", "mode=5", "fontsize=18",
                      "color=13905189", "progress=61500", "pool=0", "csrf=T"] {
            XCTAssertTrue(body.contains(field), "\(field) missing from \(body)")
        }
        XCTAssertFalse(body.contains("colorful"), body)
        XCTAssertEqual(rig.sender.text, "")
        XCTAssertTrue(rig.danmaku.pendingItems(atMs: 61_516).contains { $0.isOwn })
    }

    func testGradientSendsWhiteWithTheColourfulFlag() async throws {
        let rig = try await makeRig(vip: true)
        rig.sender.style.gradient = true
        rig.sender.style.color = 0x42954C
        rig.sender.text = "渐变"
        let failure = await rig.sender.send()
        XCTAssertNil(failure)
        let body = String(decoding: rig.http.requests(to: postPath).first?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("color=16777215"), body)
        XCTAssertTrue(body.contains("colorful=60001"), body)
    }

    func testGradientNeedsAMembership() async throws {
        let rig = try await makeRig(vip: false)
        rig.sender.style.gradient = true
        rig.sender.text = "渐变"
        let failure = await rig.sender.send()
        XCTAssertEqual(failure, "开通大会员后可使用")
        XCTAssertTrue(rig.http.requests(to: postPath).isEmpty)
        XCTAssertEqual(rig.sender.text, "渐变")
    }

    func testLoggedOutAsksForLoginWithoutARequest() async throws {
        let rig = try await makeRig(loggedIn: false)
        rig.sender.text = "你好"
        let failure = await rig.sender.send()
        XCTAssertEqual(failure, "需要登录")
        XCTAssertTrue(rig.sender.needsLogin)
        XCTAssertTrue(rig.http.requests(to: postPath).isEmpty)
        XCTAssertEqual(rig.sender.text, "你好")
    }

    func testExpiredLoginAsksForLoginAndKeepsTheText() async throws {
        let rig = try await makeRig(transport: PostHTTP(#"{"code":-101,"message":"账号未登录","ttl":1}"#))
        rig.sender.text = "你好"
        let failure = await rig.sender.send()
        XCTAssertEqual(failure, "需要登录")
        XCTAssertTrue(rig.sender.needsLogin)
        XCTAssertEqual(rig.sender.text, "你好")
        XCTAssertFalse(rig.danmaku.pendingItems(atMs: 0).contains { $0.isOwn })
    }

    func testServerRefusalShowsItsMessage() async throws {
        let rig = try await makeRig(transport: PostHTTP(#"{"code":36703,"message":"弹幕发送过于频繁","ttl":1}"#))
        rig.sender.text = "你好"
        let failure = await rig.sender.send()
        XCTAssertEqual(failure, "弹幕发送过于频繁")
        XCTAssertFalse(rig.sender.needsLogin)
        XCTAssertEqual(rig.sender.text, "你好")
    }

    func testEmptyTextSendsNothing() async throws {
        let rig = try await makeRig()
        rig.sender.text = "  \n "
        let failure = await rig.sender.send()
        XCTAssertNil(failure)
        XCTAssertTrue(rig.http.requests(to: postPath).isEmpty)
    }

    func testClosedVideoRefusesToSend() async throws {
        let rig = try await makeRig(transport: ClosedHTTP())
        rig.danmaku.load(cid: F.cidA1, bvid: F.bvidA, durationMs: 200_000)
        rig.danmaku.update(positionMs: 0, playing: true)
        await rig.danmaku.settle()
        XCTAssertTrue(rig.danmaku.closed)
        rig.sender.text = "你好"
        let failure = await rig.sender.send()
        XCTAssertEqual(failure, "UP主已关闭弹幕")
        XCTAssertTrue(rig.http.requests(to: postPath).isEmpty)
    }

    func testTextIsCappedAt100Characters() async throws {
        let rig = try await makeRig()
        rig.sender.text = String(repeating: "弹", count: 150)
        XCTAssertEqual(rig.sender.text.count, 100)
        rig.sender.text = "a" + String(repeating: "😀", count: 120)
        XCTAssertEqual(rig.sender.text.count, 100)
    }

    /// The bar fills the page and reads the safe area itself, so it must follow the page into landscape and back.
    func testSendBarFollowsTheScreenIntoLandscapeAndBack() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let rig = try await makeRig()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DanmakuSendBar(model: rig.sender, onClose: {}, demo: .style))
        window.makeKeyAndVisible()
        let orientation = OrientationController.shared
        defer {
            window.isHidden = true
            orientation.exitToInline()
        }
        let view = try XCTUnwrap(window.rootViewController?.view)

        orientation.enterLandscape()
        let turned = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation.isLandscape }
        XCTAssertTrue(turned, "the scene never turned to landscape")
        let wide = await waitUntil(3) { view.bounds.width > view.bounds.height }
        XCTAssertTrue(wide, "the bar was not laid out for landscape")

        orientation.exitToInline()
        let back = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        XCTAssertTrue(back, "the scene never turned back to portrait")
        let tall = await waitUntil(3) { view.bounds.height > view.bounds.width }
        XCTAssertTrue(tall)
        XCTAssertTrue(view.window === window)
    }

    // MARK: helpers

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private final class PostHTTP: FixtureHTTP, @unchecked Sendable {
        let reply: String

        init(_ reply: String) {
            self.reply = reply
            super.init()
        }

        override func answer(_ request: HTTPRequest) -> (Int, Data) {
            request.url.path == "/x/v2/dm/post" ? (200, Data(reply.utf8)) : super.answer(request)
        }
    }

    private final class ClosedHTTP: FixtureHTTP, @unchecked Sendable {
        override func answer(_ request: HTTPRequest) -> (Int, Data) {
            request.url.path.hasSuffix("/seg.so") ? (200, DanmakuFixtures.segment(index: 1, closed: true)) : super.answer(request)
        }
    }

    private struct Rig {
        let sender: DanmakuSendModel
        let danmaku: DanmakuController
        let http: FixtureHTTP
    }

    private func makeRig(position: Double = 12, loggedIn: Bool = true, vip: Bool = false,
                         transport: FixtureHTTP = FixtureHTTP()) async throws -> Rig {
        let client = BiliClient(transport: transport, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let suite = "danmaku-send-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let page = VideoPageModel(route: VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: position), client: client,
                                  settings: settings, account: { .loggedOut }, makeController: { FakePlayback(item: $0) })
        await page.load()
        let danmaku = DanmakuController(client: client, settings: settings, ownHash: { nil })
        danmaku.load(cid: F.cidA1, bvid: F.bvidA, durationMs: 200_000)
        let sender = DanmakuSendModel(client: client, page: page, danmaku: danmaku, isVip: { vip }, isLoggedIn: { loggedIn })
        return Rig(sender: sender, danmaku: danmaku, http: transport)
    }
}
