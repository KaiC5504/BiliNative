import SwiftUI
import UIKit
import XCTest
import AppLogic
import BiliAPI
@testable import BiliNative

@MainActor
final class IntroTabTests: XCTestCase {
    private typealias F = VideoPageFixtures

    func testCollectionPositionFindsTheEpisodeByCid() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidB, cid: F.cidB, startSeconds: 0))
        await page.model.load()
        let season = try XCTUnwrap(page.model.detail?.season)
        XCTAssertEqual(CollectionPosition.label(page.model.current, in: season), "2/3")
        XCTAssertEqual(CollectionPosition.section(of: page.model.current, in: season)?.id, 6001)
        // A part the 合集 does not list is placed by its video.
        XCTAssertEqual(CollectionPosition.label(PlayItem(bvid: F.bvidA, cid: F.cidA2), in: season), "1/3")
        XCTAssertEqual(CollectionPosition.section(of: PlayItem(bvid: F.bvidC, cid: F.cidC), in: season)?.id, 6002)
    }

    func testDescriptionTimestampSeeksThePlayer() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        await page.model.load()
        let fake = try XCTUnwrap(page.fakes.all.first)
        let runs = TitleBlock.descriptionRuns(try XCTUnwrap(page.model.detail).descParts)
        let timestamp = try XCTUnwrap(runs.first { if case .timestamp = $0 { return true } else { return false } })
        XCTAssertEqual(timestamp, .timestamp(label: "03:15", seconds: 195))
        XCTAssertEqual(runs.last, .mention(name: "演示UP主", mid: 42))

        let tapped = try XCTUnwrap(RichLink.url(for: timestamp).flatMap(RichLink.run(for:)))
        fake.pause()
        await page.model.activate(tapped)
        XCTAssertEqual(fake.seeks, [195])
        XCTAssertTrue(fake.isPlaying)
    }

    func testRelatedTapPushesANewRoute() async throws {
        let page = makePage(VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        await page.model.load()
        try await waitUntil { !page.model.related.isEmpty }
        let card = page.model.related[0]
        page.model.openRelated(card)
        XCTAssertEqual(page.navigator.path.count, 1)
        guard case .video(let pushed)? = page.navigator.path.last else { return XCTFail("no video page on the path") }
        XCTAssertEqual(pushed.bvid, card.bvid)
        XCTAssertNil(pushed.cid)
        XCTAssertNil(pushed.startSeconds)
        XCTAssertEqual(page.model.current?.bvid, F.bvidA, "the page itself keeps playing its own video")
    }

    func testCollapsingPlayerShrinksOnlyWhilePaused() {
        let player = CollapsingPlayer(fullHeight: 220)
        XCTAssertEqual(player.height(forOffset: 500, paused: false), 220)
        XCTAssertEqual(player.height(forOffset: 0, paused: true), 220)
        XCTAssertEqual(player.height(forOffset: -40, paused: true), 220, "pulling down at the top")
        XCTAssertEqual(player.height(forOffset: 100, paused: true), 120)
        XCTAssertEqual(player.height(forOffset: 500, paused: true), 56)
        XCTAssertEqual(player.progress(height: 220), 0)
        XCTAssertEqual(player.progress(height: 56), 1)
    }

    func testUploaderAndTagsLoadForEveryoneAndTheRelationOnlyWhenLoggedIn() async throws {
        let loggedOut = makePage(VideoRoute(bvid: F.bvidB, cid: F.cidB, startSeconds: 0))
        await loggedOut.model.load()
        try await waitUntil { loggedOut.model.uploader != nil && !loggedOut.model.tags.isEmpty }
        XCTAssertEqual(loggedOut.model.uploader?.fans, 475_000)
        XCTAssertEqual(loggedOut.model.uploader?.isVip, true)
        XCTAssertEqual(loggedOut.model.tags.filter { $0.kind != .normal }.count, 2)
        XCTAssertNil(loggedOut.model.relation)
        XCTAssertTrue(loggedOut.http.requests(to: "/x/web-interface/archive/relation").isEmpty)

        let loggedIn = makePage(VideoRoute(bvid: F.bvidB, cid: F.cidB, startSeconds: 0), loggedIn: true)
        await loggedIn.model.load()
        try await waitUntil { loggedIn.model.relation != nil }
        XCTAssertEqual(loggedIn.model.relation?.like, false)
    }

    // MARK: helpers

    private final class Fakes {
        var all: [FakePlayback] = []
    }

    private struct Page {
        let model: VideoPageModel
        let fakes: Fakes
        let http: FixtureHTTP
        let navigator: AppNavigator
    }

    private func makePage(_ route: VideoRoute, loggedIn: Bool = false) -> Page {
        let fakes = Fakes()
        let http = FixtureHTTP()
        let account: AppEnvironment.Account = loggedIn ? .loggedIn(name: "测试", vip: false) : .loggedOut
        let client = BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
        let suite = "intro-tab-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let navigator = AppNavigator()
        let model = VideoPageModel(route: route, client: client, settings: settings, account: { account },
                                   makeController: { item, player in
                                       let fake = FakePlayback(item: item, player: player)
                                       fakes.all.append(fake)
                                       return fake
                                   },
                                   sleep: { _ in _ = try? await Task.sleep(nanoseconds: 3_600_000_000_000) },
                                   openPage: { navigator.open($0) })
        return Page(model: model, fakes: fakes, http: http, navigator: navigator)
    }

    private func waitUntil(_ seconds: Double = 5, _ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("timed out", file: file, line: line)
    }
}

/// A related video pushes a whole second video page, player host and all, through the app navigator; back pops it.
@MainActor
final class RelatedPushTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private var window: UIWindow?

    override func setUp() async throws {
        UserDefaults.standard.set(true, forKey: "DemoData")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "DemoData")
        PiPKeeper.shared.release()
        window?.isHidden = true
        window = nil
    }

    func testRelatedVideoPushesAPageAndBackReturns() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let env = AppEnvironment()
        let model = env.makeVideoPageModel(route: VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: StackRoot(navigator: env.navigator).environment(env))
        env.navigator.show(model)
        window.makeKeyAndVisible()
        self.window = window

        let loaded = await waitUntil(10) { !model.related.isEmpty && Self.hosts(in: window).count == 1 }
        XCTAssertTrue(loaded, "the first page never loaded")
        let first = try XCTUnwrap(Self.hosts(in: window).first)
        let card = model.related[0]

        model.openRelated(card)
        let pushed = await waitUntil(8) { Self.hosts(in: window).contains { $0 !== first } }
        XCTAssertTrue(pushed, "no second page came up")
        guard case .video(let pushedRoute)? = env.navigator.path.last else { return XCTFail("no video page on the path") }
        XCTAssertEqual(pushedRoute.bvid, card.bvid)
        let covered = await waitUntil(5) { model.covered }
        XCTAssertTrue(covered, "the page under the related video should be covered, not closed")
        XCTAssertFalse(model.closed)

        env.navigator.path.removeLast()
        let back = await waitUntil(8) { Self.hosts(in: window).map(ObjectIdentifier.init) == [ObjectIdentifier(first)] }
        XCTAssertTrue(back, "the first page did not come back alone: \(Self.hosts(in: window).count) hosts")
        let uncovered = await waitUntil(5) { !model.covered }
        XCTAssertTrue(uncovered)
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private static func hosts(in view: UIView) -> [PlayerHostView] {
        (view as? PlayerHostView).map { [$0] } ?? view.subviews.flatMap { hosts(in: $0) }
    }
}

private struct StackRoot: View {
    @Bindable var navigator: AppNavigator

    var body: some View {
        NavigationStack(path: $navigator.path) {
            Color.clear.videoPageDestinations()
        }
    }
}
