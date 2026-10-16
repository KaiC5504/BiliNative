import XCTest
import AppLogic
import BiliAPI
@testable import BiliNative

@MainActor
final class ChromeStateTests: XCTestCase {
    private typealias F = VideoPageFixtures
    private let size = CGSize(width: 400, height: 225)

    func testControlsHideThreeSecondsAfterTheLastTouchButNotWhileScrubbing() async throws {
        let clock = ManualSleeper()
        let chrome = ChromeState(sleep: { await clock.sleep($0) })

        chrome.touch()
        XCTAssertTrue(chrome.visible)
        try await waitUntil { clock.pending == 1 }
        XCTAssertEqual(clock.requested, [3])
        // A second touch restarts the timer, so the first one running out hides nothing.
        chrome.touch()
        try await waitUntil { clock.pending == 2 }
        clock.fireOldest()
        await settle()
        XCTAssertTrue(chrome.visible)
        clock.fireOldest()
        try await waitUntil { !chrome.visible }

        chrome.touch()
        chrome.scrubbing = 50
        try await waitUntil { clock.pending == 1 }
        clock.fireAll()
        await settle()
        XCTAssertTrue(chrome.visible, "the controls stay while the bar is being dragged")

        chrome.scrubbing = nil
        try await waitUntil { clock.pending == 1 }
        clock.fireAll()
        try await waitUntil { !chrome.visible }

        chrome.panelOpen = true
        chrome.touch()
        try await waitUntil { clock.pending == 1 }
        clock.fireAll()
        await settle()
        XCTAssertTrue(chrome.visible, "the controls stay while a panel is open")
    }

    func testHoldDoublesTheRateAndReleaseRestoresIt() async throws {
        let (page, fake) = try await playingPage()
        page.rate = 1.25
        XCTAssertEqual(fake.rate, 1.25)
        let chrome = ChromeState()

        chrome.handle(.holdBegan, page: page, size: size)
        XCTAssertEqual(fake.rate, 2)
        XCTAssertEqual(chrome.hud, .speedUp)
        XCTAssertFalse(chrome.visible, "the controls stay hidden while held (25)")
        XCTAssertEqual(page.rate, 1.25, "the 倍速 choice is not changed by holding")

        chrome.handle(.holdEnded, page: page, size: size)
        XCTAssertEqual(fake.rate, 1.25)
        XCTAssertNil(chrome.hud)
    }

    func testHorizontalDragSeeksNinetySecondsPerWidthOnRelease() async throws {
        let (page, fake) = try await playingPage()
        fake.position = 100
        let chrome = ChromeState()

        chrome.handle(.seekChanged(dx: 80), page: page, size: size)
        XCTAssertEqual(chrome.scrubbing, 118)
        XCTAssertEqual(chrome.hud, .seek(label: "01:58/03:20"))
        XCTAssertEqual(fake.seeks, [], "nothing seeks until the finger lifts")

        chrome.handle(.seekEnded(dx: 200), page: page, size: size)
        XCTAssertNil(chrome.hud)
        try await waitUntil { fake.seeks == [145] }
        try await waitUntil { chrome.scrubbing == nil }
    }

    func testDoubleTapTogglesPlayback() async throws {
        let (page, fake) = try await playingPage()
        XCTAssertTrue(fake.isPlaying)
        let chrome = ChromeState()

        chrome.handle(.doubleTap, page: page, size: size)
        XCTAssertFalse(fake.isPlaying)
        XCTAssertTrue(chrome.visible)
        chrome.handle(.doubleTap, page: page, size: size)
        XCTAssertTrue(fake.isPlaying)

        chrome.handle(.tap, page: page, size: size)
        XCTAssertFalse(chrome.visible)
        chrome.handle(.tap, page: page, size: size)
        XCTAssertTrue(chrome.visible)
    }

    // MARK: helpers

    private final class Box {
        var fake: FakePlayback?
    }

    private func playingPage() async throws -> (VideoPageModel, FakePlayback) {
        let box = Box()
        let suite = "chrome-state-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BiliClient(transport: FixtureHTTP(), cookies: CookieJar())
        let model = VideoPageModel(route: VideoRoute(bvid: F.bvidA, cid: F.cidA1, startSeconds: 0), client: client,
                                   settings: AppSettings(defaults: UserDefaults(suiteName: suite)!),
                                   account: { .loggedOut },
                                   makeController: { item in
                                       let fake = FakePlayback(item: item)
                                       box.fake = fake
                                       return fake
                                   })
        await model.load()
        let fake = try XCTUnwrap(box.fake)
        XCTAssertTrue(fake.isPlaying)
        return (model, fake)
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
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

/// Stands in for the hide timer's sleep: each sleep waits until the test lets it finish.
@MainActor
private final class ManualSleeper {
    private(set) var requested: [Double] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var pending: Int { waiting.count }

    func sleep(_ seconds: Double) async {
        requested.append(seconds)
        await withCheckedContinuation { waiting.append($0) }
    }

    func fireOldest() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    func fireAll() {
        let all = waiting
        waiting = []
        all.forEach { $0.resume() }
    }
}
