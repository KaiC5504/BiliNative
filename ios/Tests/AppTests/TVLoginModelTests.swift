import Observation
import SwiftUI
import XCTest
import BiliAPI
@testable import BiliNative

/// Answers each path from a queue of bodies (the last one repeats) and records every request.
final class ScriptedHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [HTTPRequest] = []
    private var routes: [String: [String]]
    private var served: [String: Int] = [:]

    init(_ routes: [String: [String]]) {
        self.routes = routes
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = lock.withLock { () -> String in
            log.append(request)
            let path = request.url.path
            let queue = routes[path] ?? [#"{"code":0,"message":"0","ttl":1,"data":null}"#]
            let index = served[path, default: 0]
            served[path] = index + 1
            return queue[min(index, queue.count - 1)]
        }
        return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8), finalURL: request.url)
    }

    func requests(to path: String) -> [HTTPRequest] {
        lock.withLock { log.filter { $0.url.path == path } }
    }

    func body(of path: String, at index: Int = 0) -> String {
        let found = requests(to: path)
        guard found.indices.contains(index) else { return "" }
        return String(decoding: found[index].body ?? Data(), as: UTF8.self)
    }

    var total: Int { lock.withLock { log.count } }
}

enum TVLoginFixtures {
    static let authCodePath = "/x/passport-tv-login/qrcode/auth_code"
    static let pollPath = "/x/passport-tv-login/qrcode/poll"
    static let signer = AppSigner(appKey: "testkey", appSecret: "testsecret")

    static let authCode = #"{"code":0,"message":"0","ttl":1,"data":{"url":"https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1","auth_code":"AUTH1"}}"#
    static let waiting = #"{"code":86039,"message":"二维码尚未确认","ttl":1,"data":null}"#
    static let scanned = #"{"code":86090,"message":"二维码已扫码未确认","ttl":1,"data":null}"#
    static let expired = #"{"code":86038,"message":"二维码已失效","ttl":1,"data":null}"#
    static let confirmed = #"{"code":0,"message":"0","ttl":1,"data":{"access_token":"tok-1","mid":42}}"#

    static func client(_ http: ScriptedHTTP) -> BiliClient {
        BiliClient(transport: http, cookies: CookieJar(["SESSDATA": "s", "bili_jct": "T", "buvid3": "b3", "buvid4": "b4"]))
    }
}

@MainActor
final class TVLoginModelTests: XCTestCase {
    override func setUp() async throws {
        AppTokenStore.delete()
    }

    override func tearDown() async throws {
        AppTokenStore.delete()
    }

    private final class Sleeps: @unchecked Sendable {
        var values: [Double] = []
    }

    func testNoKeysMeansUnavailable() async {
        let http = ScriptedHTTP([:])
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: nil, sleep: { _ in })
        await model.start()
        XCTAssertEqual(model.state, .unavailable)
        XCTAssertEqual(http.total, 0)
        XCTAssertNil(AppTokenStore.load())
    }

    func testPollsUntilConfirmedAndStoresTheToken() async {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting, TVLoginFixtures.scanned, TVLoginFixtures.confirmed]])
        let sleeps = Sleeps()
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { sleeps.values.append($0) })
        XCTAssertEqual(model.state, .starting)
        await model.start()
        XCTAssertEqual(model.state, .done)
        XCTAssertEqual(AppTokenStore.load(), "tok-1")
        XCTAssertEqual(http.requests(to: TVLoginFixtures.pollPath).count, 3)
        XCTAssertEqual(sleeps.values, [2, 2, 2])
        XCTAssertTrue(http.body(of: TVLoginFixtures.pollPath).contains("auth_code=AUTH1"))
    }

    func testTheConfirmPageComesFromTheAuthCodeReply() async throws {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting]])
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { _ in })
        let run = Task { await model.start() }
        while http.requests(to: TVLoginFixtures.pollPath).isEmpty { await Task.yield() }
        let expected = try XCTUnwrap(URL(string: "https://passport.bilibili.com/h5-app/passport/auth/scan?qrcode_id=QR1"))
        XCTAssertEqual(model.state, .confirming(url: expected))
        model.cancel()
        await run.value
    }

    func testExpiredCodeEndsInExpired() async {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting, TVLoginFixtures.expired]])
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { _ in })
        await model.start()
        XCTAssertEqual(model.state, .expired)
        XCTAssertNil(AppTokenStore.load())
        XCTAssertEqual(http.requests(to: TVLoginFixtures.pollPath).count, 2)
    }

    func testRetryAfterExpiryAsksForAFreshCode() async {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.expired, TVLoginFixtures.confirmed]])
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { _ in })
        await model.start()
        XCTAssertEqual(model.state, .expired)
        await model.start()
        XCTAssertEqual(model.state, .done)
        XCTAssertEqual(http.requests(to: TVLoginFixtures.authCodePath).count, 2)
        XCTAssertEqual(AppTokenStore.load(), "tok-1")
    }

    func testCancelStopsThePolling() async {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting]])
        let box = ModelBox()
        let sleeps = Sleeps()
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { seconds in
            sleeps.values.append(seconds)
            // The sheet closes while the loop is waiting out its interval.
            if sleeps.values.count == 2 { box.model?.cancel() }
        })
        box.model = model
        await model.start()
        XCTAssertEqual(http.requests(to: TVLoginFixtures.pollPath).count, 1)
        XCTAssertNil(AppTokenStore.load())
        if case .confirming = model.state {} else { XCTFail("\(model.state)") }
    }

    func testAServerRefusalFailsWithItsMessage() async {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [#"{"code":-400,"message":"请求错误","ttl":1}"#]])
        let model = TVLoginModel(client: TVLoginFixtures.client(http), signer: TVLoginFixtures.signer, sleep: { _ in })
        await model.start()
        XCTAssertEqual(model.state, .failed("请求错误"))
    }

    @MainActor
    private final class ModelBox {
        var model: TVLoginModel?
    }
}

@Observable
@MainActor
final class TVGateDriver {
    var requested = false
}

private struct TVGateHarness: View {
    @Bindable var driver: TVGateDriver
    let makeModel: () -> TVLoginModel

    var body: some View {
        Color.white.ignoresSafeArea().tvLoginGate($driver.requested, makeModel: makeModel, onDone: {})
    }
}

/// Hosts the gate in a window and presents the real sheet over it, the way the page does.
@MainActor
final class TVLoginSheetPresentationTests: XCTestCase {
    private var window: UIWindow?
    private let driver = TVGateDriver()

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        AppTokenStore.delete()
        let orientation = OrientationController.shared
        orientation.locked = false
        orientation.exitToInline()
        if let scene = Self.scene {
            _ = await waitUntil(5) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        }
    }

    func testTVLoginSheetPresentsAndDismisses() async throws {
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting]])
        var created: TVLoginModel?
        let window = try await show(http) { created = $0 }

        driver.requested = true
        let shown = await waitUntil(5) { window.rootViewController?.presentedViewController != nil }
        XCTAssertTrue(shown, "the sheet never came up")
        XCTAssertFalse(driver.requested)
        let model = try XCTUnwrap(created)
        let polling = await waitUntil(5) { !http.requests(to: TVLoginFixtures.pollPath).isEmpty }
        XCTAssertTrue(polling, "the sheet never started the login: \(model.state)")

        window.rootViewController?.dismiss(animated: false)
        let gone = await waitUntil(5) { window.rootViewController?.presentedViewController == nil }
        XCTAssertTrue(gone, "the sheet did not go away")

        // Closing the sheet ends the polling.
        try await Task.sleep(for: .milliseconds(200))
        let settled = http.requests(to: TVLoginFixtures.pollPath).count
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(http.requests(to: TVLoginFixtures.pollPath).count, settled)

        driver.requested = true
        let again = await waitUntil(5) { window.rootViewController?.presentedViewController != nil }
        XCTAssertTrue(again, "the sheet did not come up a second time")
        XCTAssertFalse(created === model, "a second presentation should start a fresh login")
    }

    func testTVLoginSheetFromFullScreenGoesBackToInlineFirst() async throws {
        let scene = try XCTUnwrap(Self.scene)
        let http = ScriptedHTTP([TVLoginFixtures.authCodePath: [TVLoginFixtures.authCode],
                                 TVLoginFixtures.pollPath: [TVLoginFixtures.waiting]])
        let window = try await show(http) { _ in }
        let orientation = OrientationController.shared
        orientation.enterLandscape()
        let turned = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation.isLandscape }
        XCTAssertTrue(turned, "the scene never turned to landscape")

        driver.requested = true
        let shown = await waitUntil(8) { window.rootViewController?.presentedViewController != nil }
        XCTAssertTrue(shown, "the sheet never came up")
        XCTAssertEqual(orientation.presentation, .inline)
        let upright = await waitUntil(8) { scene.effectiveGeometry.interfaceOrientation == .portrait }
        XCTAssertTrue(upright, "the page stayed rotated behind the sheet")
    }

    private func show(_ http: ScriptedHTTP, created: @escaping (TVLoginModel) -> Void) async throws -> UIWindow {
        let scene = try XCTUnwrap(Self.scene)
        let window = UIWindow(windowScene: scene)
        let client = TVLoginFixtures.client(http)
        window.rootViewController = UIHostingController(rootView: TVGateHarness(driver: driver, makeModel: {
            let model = TVLoginModel(client: client, signer: TVLoginFixtures.signer,
                                     sleep: { _ in try? await Task.sleep(for: .milliseconds(50)) })
            created(model)
            return model
        }))
        window.makeKeyAndVisible()
        self.window = window
        let laidOut = await waitUntil(5) { (window.rootViewController?.view.bounds.width ?? 0) > 0 }
        XCTAssertTrue(laidOut, "the host never laid out")
        // onChange only sees changes made after the first pass has attached it.
        try await Task.sleep(for: .milliseconds(500))
        return window
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
