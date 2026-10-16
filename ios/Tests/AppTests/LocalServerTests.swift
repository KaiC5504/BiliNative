import XCTest
@testable import BiliNative

final class LocalServerTests: XCTestCase {
    func testServesPlaylistsAndRanges() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let token = DebugSupport.registerStaticAssets(on: server, size: 10_000)

        let playlistURL = try XCTUnwrap(server.url(token: token, name: "master.m3u8"))
        let (playlist, playlistResponse) = try await URLSession.shared.data(from: playlistURL)
        XCTAssertEqual((playlistResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: playlist, as: UTF8.self), "#EXTM3U\n")

        var request = URLRequest(url: try XCTUnwrap(server.url(token: token, name: "v.mp4")))
        request.setValue("bytes=50-149", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 50-149/10000")
        XCTAssertEqual(Array(bytes), DebugSupport.staticContent(size: 10_000, range: 50...149))

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port!)/nope/master.m3u8")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }

    func testHeadSendsHeadersWithoutReadingMedia() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let reads = ReadCounter()
        let token = DebugSupport.registerStaticAssets(on: server, size: 10_000) { reads.increment() }

        var request = URLRequest(url: try XCTUnwrap(server.url(token: token, name: "v.mp4")))
        request.httpMethod = "HEAD"
        request.setValue("bytes=500-1499", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), "1000")
        XCTAssertTrue(bytes.isEmpty)
        XCTAssertEqual(reads.value, 0)

        var playlistRequest = URLRequest(url: try XCTUnwrap(server.url(token: token, name: "master.m3u8")))
        playlistRequest.httpMethod = "HEAD"
        let (playlist, playlistResponse) = try await URLSession.shared.data(for: playlistRequest)
        XCTAssertEqual((playlistResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(playlist.isEmpty)

        request.httpMethod = "GET"
        _ = try await URLSession.shared.data(for: request)
        XCTAssertEqual(reads.value, 1)
    }

    func testPrepareParsesSidxAndKeepsTheInitInMemory() async throws {
        let fixture = DebugSupport.headerFixture(withMoov: true)
        let prepared = try await PlaybackBuilder.prepare(choice: fixture.choice) { _, _ in (fixture.bytes, fixture.total) }
        XCTAssertEqual(prepared.video.segments.count, 1)
        XCTAssertEqual(prepared.audio.segments.count, 1)
        XCTAssertFalse(prepared.rewroteHEV1)
        let playlists = PlaybackBuilder.directPlaylists(prepared, token: "t")
        XCTAssertEqual(Set(playlists.keys), ["master.m3u8", "v.m3u8", "a.m3u8"])
        let video = try XCTUnwrap(playlists["v.m3u8"])
        XCTAssertTrue(video.contains("#EXT-X-MAP:URI=\"https://primary.invalid/upgcxcode/80.m4s?deadline=1&upsig=sig\",BYTERANGE=\"24@0\""))
        XCTAssertTrue(video.contains("#EXT-X-BYTERANGE:1000@68"))
        let master = try XCTUnwrap(playlists["master.m3u8"])
        XCTAssertTrue(master.contains("bilinative://playlist/t/v.m3u8"))
        XCTAssertTrue(master.contains("URI=\"bilinative://playlist/t/a.m3u8\""))
    }

    func testPrepareRejectsHeadersWithoutACompleteMoov() async {
        let fixture = DebugSupport.headerFixture(withMoov: false)
        do {
            _ = try await PlaybackBuilder.prepare(choice: fixture.choice) { _, _ in (fixture.bytes, fixture.total) }
            XCTFail("expected PlaybackError.noSidx")
        } catch {
            XCTAssertEqual(error as? PlaybackError, .noSidx)
        }
    }

    func testDirectModePlaysFromTheFirstAddressThatAnswers() async throws {
        let fixture = DebugSupport.headerFixture(withMoov: true, backupHosts: ["whole.invalid", "skewed.invalid", "backup.invalid"])
        let transport = DebugSupport.FixtureTransport(bytes: fixture.bytes, total: fixture.total,
                                                      answers: ["primary.invalid": .refuse, "whole.invalid": .wholeFile,
                                                                "skewed.invalid": .wrongRange])
        let prepared = try await PlaybackBuilder.prepareDirect(choice: fixture.choice, transport: transport)
        XCTAssertTrue(prepared.video.mediaURL.hasPrefix("https://backup.invalid/"))
        XCTAssertTrue(prepared.audio.mediaURL.hasPrefix("https://backup.invalid/"))
        let playlists = PlaybackBuilder.directPlaylists(prepared, token: "t")
        for name in ["v.m3u8", "a.m3u8"] {
            let playlist = try XCTUnwrap(playlists[name])
            XCTAssertTrue(playlist.contains("https://backup.invalid/"), name)
            for refused in ["primary.invalid", "whole.invalid", "skewed.invalid"] {
                XCTAssertFalse(playlist.contains(refused), "\(name) \(refused)")
            }
        }

        let open = DebugSupport.FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: [:])
        let direct = try await PlaybackBuilder.prepareDirect(choice: fixture.choice, transport: open)
        XCTAssertTrue(direct.video.mediaURL.hasPrefix("https://primary.invalid/"))
    }

    func testDirectModeFailsTypedWhenEveryAddressRefuses() async {
        let fixture = DebugSupport.headerFixture(withMoov: true)
        let transport = DebugSupport.FixtureTransport(bytes: fixture.bytes, total: fixture.total,
                                                      answers: ["primary.invalid": .refuse, "backup.invalid": .refuse])
        do {
            _ = try await PlaybackBuilder.prepareDirect(choice: fixture.choice, transport: transport)
            XCTFail("expected PlaybackError.noSource")
        } catch {
            XCTAssertEqual(error as? PlaybackError, .noSource)
        }
    }

    func testDirectModeMovesOnFromAnAddressThatHangs() async throws {
        let fixture = DebugSupport.headerFixture(withMoov: true)
        let transport = DebugSupport.HangingTransport(inner: DebugSupport.FixtureTransport(bytes: fixture.bytes, total: fixture.total, answers: [:]),
                                                      hangingHosts: ["primary.invalid"])
        let started = Date()
        let prepared = try await PlaybackBuilder.prepareDirect(choice: fixture.choice, transport: transport, candidateSeconds: 0.3)
        XCTAssertEqual(prepared.video.mediaURL, fixture.choice.video.backupURLs[0])
        XCTAssertEqual(prepared.audio.mediaURL, fixture.choice.audio.backupURLs[0])
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "both tracks wait out the hanging address at the same time")
    }

    func testStartAfterStopDuringStartBeginsANewListener() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        defer { server.stop() }
        let first = Task { try await server.start() }
        let deadline = Date().addingTimeInterval(5)
        while server.state == .stopped, Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        server.stop()
        try await server.start()
        _ = try? await first.value
        XCTAssertTrue(server.isRunning)
        let token = DebugSupport.registerStaticAssets(on: server, size: 1_000)
        let (_, response) = try await URLSession.shared.data(from: try XCTUnwrap(server.url(token: token, name: "master.m3u8")))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testClientDisconnectEndsTheEngineReadPromptly() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let readStarted = expectation(description: "read started")
        readStarted.assertForOverFulfill = false
        let readEnded = expectation(description: "read ended")
        let token = DebugSupport.registerHangingAsset(on: server, onRead: { readStarted.fulfill() }, onEnd: { readEnded.fulfill() })

        let task = URLSession.shared.dataTask(with: try XCTUnwrap(server.url(token: token, name: "hang.mp4")))
        task.resume()
        await fulfillment(of: [readStarted], timeout: 5)
        task.cancel()
        await fulfillment(of: [readEnded], timeout: 1.5)
    }

    func testDirectPlaylistURLsKeepTheTokenInThePath() {
        let loader = DirectPlaylistLoader()
        let url = loader.register(token: "AbC09", playlists: ["master.m3u8": "#EXTM3U\n"])
        XCTAssertEqual(url.absoluteString, "bilinative://playlist/AbC09/master.m3u8")
        XCTAssertEqual(url.pathComponents, ["/", "AbC09", "master.m3u8"])
    }
}

private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
