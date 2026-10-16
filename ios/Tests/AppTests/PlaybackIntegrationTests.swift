import AVFoundation
import XCTest
@testable import BiliNative

@MainActor
final class PlaybackIntegrationTests: XCTestCase {
    private var mediaDirectory: URL!
    private var nodes: [FakeCDNServer] = []
    private var ports: [UInt16] = []
    private var server: LocalServer!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["MEDIA_DIR"] else {
            throw XCTSkip("MEDIA_DIR not set; CI generates it with ios/scripts/make_test_media.py")
        }
        mediaDirectory = URL(fileURLWithPath: path)
        nodes = [FakeCDNServer(directory: mediaDirectory), FakeCDNServer(directory: mediaDirectory)]
        ports = []
        for node in nodes { ports.append(try await node.start()) }
        server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
    }

    override func tearDown() async throws {
        nodes.forEach { $0.stop() }
        server?.stop()
    }

    private func makeController(variant: String, codecid: Int, btr: Bool,
                                refusedPrimary: Bool = false) throws -> (PlaybackController, FixtureProvider) {
        let media = try FixtureMedia.load(directory: mediaDirectory, variant: variant)
        let environment = FixturePlayback.make(media: media, codecid: codecid, ports: ports, server: server, router: server.router,
                                               loader: DirectPlaylistLoader(), refusedPrimary: refusedPrimary)
        let provider = try XCTUnwrap(environment.provider as? FixtureProvider)
        return (PlaybackController(environment: environment, quality: 64, codec: codecid == 12 ? .hevc : .avc, btrEnabled: btr), provider)
    }

    private func waitUntil(_ seconds: Double, _ condition: @escaping @MainActor () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("timed out", file: file, line: line)
    }

    /// Requests AVPlayer made to the fake nodes itself, which only happens in direct mode.
    private var playerRequests: [FakeCDNServer.Request] {
        nodes.flatMap(\.requests).filter { !$0.engine }
    }

    private var engineRequests: [FakeCDNServer.Request] {
        nodes.flatMap(\.requests).filter(\.engine)
    }

    func testBTRPlaysAndSeeks() async throws {
        let (controller, _) = try makeController(variant: "avc", codecid: 7, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertEqual(controller.phase, .playing)
        XCTAssertEqual(controller.playingQuality, 64)
        XCTAssertNotNil(controller.overlay.firstFrameMs)
        _ = await controller.player.seek(to: CMTime(seconds: 20, preferredTimescale: 600))
        try await waitUntil(60) { controller.currentSeconds >= 23 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertGreaterThan(nodes.map(\.requestCount).filter { $0 > 0 }.count, 1, "both fake nodes should have served pieces")
        XCTAssertTrue(playerRequests.isEmpty, "in BTR mode only the engine talks to the CDN")
        controller.stop()
    }

    func testHEV1VideoPlaysThroughTheInitFix() async throws {
        let media = try FixtureMedia.load(directory: mediaDirectory, variant: "hevc")
        XCTAssertTrue(media.video.codecs.hasPrefix("hev1"), media.video.codecs)
        let (controller, _) = try makeController(variant: "hevc", codecid: 12, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertTrue(playerRequests.isEmpty)
        controller.stop()
    }

    func testFallsBackToDirectWhenTheServerDiesAndTheNextPlaybackRestartsIt() async throws {
        let (controller, _) = try makeController(variant: "avc", codecid: 7, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 3 }
        controller.debugKillServer()
        try await waitUntil(30) { controller.mode == .directFallback }
        try await waitUntil(60) { controller.phase == .playing }
        let resumedAt = controller.currentSeconds
        try await waitUntil(60) { controller.currentSeconds >= resumedAt + 5 }
        XCTAssertFalse(playerRequests.isEmpty, "the fallback plays from the CDN directly")
        controller.stop()

        XCTAssertFalse(server.isRunning)
        await controller.start()
        XCTAssertTrue(server.isRunning, "the next playback starts the server again")
        try await waitUntil(60) { controller.currentSeconds >= 3 }
        XCTAssertEqual(controller.mode, .ripper)
        controller.stop()
    }

    func testDirectModePlays() async throws {
        let (controller, _) = try makeController(variant: "avc", codecid: 7, btr: false)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .direct)
        XCTAssertFalse(playerRequests.isEmpty)
        controller.stop()
    }

    /// Some accounts get a primary address every node refuses next to working backups.
    func testBTRPlaysWhenOnlyTheBackupAddressWorks() async throws {
        let (controller, _) = try makeController(variant: "avc", codecid: 7, btr: true, refusedPrimary: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertTrue(playerRequests.isEmpty)
        XCTAssertTrue(engineRequests.contains { $0.status == 206 && !$0.path.hasPrefix("/refused/") })
        controller.stop()
    }

    func testDirectModePlaysFromTheBackupWhenThePrimaryIsRefused() async throws {
        let (controller, _) = try makeController(variant: "avc", codecid: 7, btr: false, refusedPrimary: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .direct)
        XCTAssertTrue(engineRequests.contains { $0.path.hasPrefix("/refused/") && $0.status == 403 }, "the primary was tried first")
        XCTAssertFalse(playerRequests.isEmpty)
        XCTAssertFalse(playerRequests.contains { $0.path.hasPrefix("/refused/") }, "AVPlayer plays the backup")
        controller.stop()
    }

    func testFailingRangesRefreshTheURLsAndThenFallBackToDirect() async throws {
        let log = CapturingLogSink()
        log.start()
        defer { log.stop() }
        let (controller, provider) = try makeController(variant: "avc", codecid: 7, btr: true)
        nodes.forEach { $0.refuseEngineMedia(true) }
        await controller.start()
        XCTAssertEqual(controller.mode, .ripper, "headers still load, so playback starts in BTR mode")
        try await waitUntil(60) { controller.mode == .directFallback }
        XCTAssertGreaterThanOrEqual(provider.calls, 2, "the URLs were refreshed before giving up on BTR mode")
        // AVPlayer failing the item in BTR mode also ends in .directFallback, with another reason.
        let entries = log.entries
        let refreshed = entries.firstIndex { $0.message == "btr range failed, refreshing urls" }
        let fellBack = entries.firstIndex { $0.message == "fallback to direct" }
        let fallback = try XCTUnwrap(fellBack, "no fallback logged")
        XCTAssertEqual(entries[fallback].fields["reason"], "btr failed again")
        XCTAssertLessThan(try XCTUnwrap(refreshed, "no refresh logged"), fallback)
        try await waitUntil(60) { controller.currentSeconds >= 3 }
        XCTAssertFalse(playerRequests.isEmpty)
        controller.stop()
    }
}
