import XCTest
import BiliShared
@testable import LocalHTTP

final class LocalHTTPTests: XCTestCase {
    func testParserStates() {
        XCTAssertEqual(HTTPRequestParser.parse(Array("GET /a HTTP/1.1\r\nHost: x\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(Array("NONSENSE\r\n\r\n".utf8)), .invalid)
        let raw = Array("GET /tok/v.mp4?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-99\r\nX-Playback-Session-Id: 1\r\n\r\n".utf8)
        guard case .complete(let head, let length) = HTTPRequestParser.parse(raw) else { return XCTFail("expected complete") }
        XCTAssertEqual(length, raw.count)
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.path, "/tok/v.mp4")
        XCTAssertEqual(head.target, "/tok/v.mp4?x=1")
        XCTAssertEqual(head.headers["range"], "bytes=0-99")
        XCTAssertEqual(head.headers["x-playback-session-id"], "1")
        XCTAssertEqual(HTTPRequestParser.parse([UInt8](repeating: 65, count: 20_000)), .invalid)
    }

    /// Review focus 4: whatever range AVPlayer sends gets the right bytes.
    func testRangeVariants() {
        XCTAssertEqual(RangeRequest.parse(nil, totalSize: 1000), .full)
        XCTAssertEqual(RangeRequest.parse("bytes=0-99", totalSize: 1000), .range(ByteRange(start: 0, end: 99)!))
        XCTAssertEqual(RangeRequest.parse("bytes=900-", totalSize: 1000), .range(ByteRange(start: 900, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=-100", totalSize: 1000), .range(ByteRange(start: 900, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=0-5000", totalSize: 1000), .range(ByteRange(start: 0, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=1000-", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=0-1,5-6", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=50-10", totalSize: 1000), .unsatisfiable)
    }

    func testRangeEdgeCases() {
        let whole = RangeRequest.range(ByteRange(start: 0, end: 999)!)
        XCTAssertEqual(RangeRequest.parse("bytes=0-", totalSize: 1000), whole)
        XCTAssertEqual(RangeRequest.parse("bytes=-5000", totalSize: 1000), whole)
        XCTAssertEqual(RangeRequest.parse("bytes=-1000", totalSize: 1000), whole)
        XCTAssertEqual(RangeRequest.parse("bytes=-1", totalSize: 1000), .range(ByteRange(start: 999, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=999-999", totalSize: 1000), .range(ByteRange(start: 999, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=999-5000", totalSize: 1000), .range(ByteRange(start: 999, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=-0", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=-", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=abc-", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=0-99", totalSize: 0), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("  Bytes=10-19 ", totalSize: 1000), .range(ByteRange(start: 10, end: 19)!))
        XCTAssertEqual(RangeRequest.parse("", totalSize: 1000), .full)
    }

    func testResponseHead() {
        let text = String(decoding: HTTPResponseWriter.head(status: 206, headers: [("Content-Length", "10")]), as: UTF8.self)
        XCTAssertEqual(text, "HTTP/1.1 206 Partial Content\r\nContent-Length: 10\r\n\r\n")
    }

    // MARK: router

    let content: [UInt8] = (0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 7) }

    func makeRouter(reads: Locked<[ByteRange]>) -> (PlaybackRouter, String) {
        let content = self.content
        let media = MediaResource(totalSize: 1000, prefix: Array(content[0..<100])) { range in
            reads.withLock { $0.append(range) }
            return AsyncThrowingStream { continuation in
                continuation.yield(Array(content[Int(range.start)...Int(range.end)]))
                continuation.finish()
            }
        }
        let router = PlaybackRouter()
        let token = router.register(PlaybackAssets(playlists: ["master.m3u8": "#EXTM3U\n"], media: ["v.mp4": media]))
        return (router, token)
    }

    func head(_ path: String, range: String? = nil, method: String = "GET") -> HTTPRequestHead {
        HTTPRequestHead(method: method, target: path, path: path, headers: range.map { ["range": $0] } ?? [:])
    }

    func body(_ result: RouteResult) async throws -> (Int, [(String, String)], [UInt8]) {
        switch result {
        case .text(let status, _, let body): return (status, [], body)
        case .failure(let status, let headers): return (status, headers, [])
        case .media(let status, let headers, let stream):
            var bytes: [UInt8] = []
            for try await chunk in stream { bytes += chunk }
            return (status, headers, bytes)
        }
    }

    func testPlaylistAndUnknownPaths() async throws {
        let (router, token) = makeRouter(reads: Locked([]))
        let playlist = try await body(router.route(head("/\(token)/master.m3u8")))
        XCTAssertEqual(playlist.0, 200)
        XCTAssertEqual(String(decoding: playlist.2, as: UTF8.self), "#EXTM3U\n")
        let wrongToken = try await body(router.route(head("/wrongtoken/master.m3u8")))
        XCTAssertEqual(wrongToken.0, 404)
        let missing = try await body(router.route(head("/\(token)/nope.mp4")))
        XCTAssertEqual(missing.0, 404)
        let post = try await body(router.route(head("/\(token)/master.m3u8", method: "POST")))
        XCTAssertEqual(post.0, 405)
        router.unregister(token)
        let afterUnregister = try await body(router.route(head("/\(token)/master.m3u8")))
        XCTAssertEqual(afterUnregister.0, 404)
    }

    func testRangesInsideAcrossAndAfterThePrefix() async throws {
        let reads = Locked<[ByteRange]>([])
        let (router, token) = makeRouter(reads: reads)

        let inside = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=0-49")))
        XCTAssertEqual(inside.0, 206)
        XCTAssertEqual(inside.2, Array(content[0...49]))
        XCTAssertTrue(inside.1.contains { $0 == ("Content-Range", "bytes 0-49/1000") })
        XCTAssertTrue(inside.1.contains { $0 == ("Content-Length", "50") })
        XCTAssertTrue(reads.current.isEmpty)

        let across = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=50-199")))
        XCTAssertEqual(across.2, Array(content[50...199]))
        XCTAssertEqual(reads.current, [ByteRange(start: 100, end: 199)!])

        let open = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=500-")))
        XCTAssertEqual(open.2, Array(content[500...999]))
        let full = try await body(router.route(head("/\(token)/v.mp4")))
        XCTAssertEqual(full.0, 200)
        let refused = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=2000-")))
        XCTAssertEqual(refused.0, 416)
        XCTAssertTrue(refused.1.contains { $0 == ("Content-Range", "bytes */1000") })
    }

    func testPrefixBoundaryAndClampedRanges() async throws {
        let reads = Locked<[ByteRange]>([])
        let (router, token) = makeRouter(reads: reads)
        let path = "/\(token)/v.mp4"

        // Ends on the last prefix byte: no read.
        let lastPrefixByte = try await body(router.route(head(path, range: "bytes=99-99")))
        XCTAssertEqual(lastPrefixByte.2, [content[99]])
        XCTAssertEqual(lastPrefixByte.1.first { $0.0 == "Content-Range" }?.1, "bytes 99-99/1000")
        XCTAssertTrue(reads.current.isEmpty)

        // Starts on the first byte after the prefix: read only.
        let firstReadByte = try await body(router.route(head(path, range: "bytes=100-100")))
        XCTAssertEqual(firstReadByte.2, [content[100]])
        XCTAssertEqual(reads.current, [ByteRange(start: 100, end: 100)!])

        // One byte on each side of the boundary.
        let straddle = try await body(router.route(head(path, range: "bytes=99-100")))
        XCTAssertEqual(straddle.0, 206)
        XCTAssertEqual(straddle.2, Array(content[99...100]))
        XCTAssertEqual(straddle.1.first { $0.0 == "Content-Length" }?.1, "2")
        XCTAssertEqual(reads.current.last, ByteRange(start: 100, end: 100)!)

        // Wide straddle, not aligned to anything.
        let wide = try await body(router.route(head(path, range: "bytes=37-613")))
        XCTAssertEqual(wide.2, Array(content[37...613]))
        XCTAssertEqual(wide.1.first { $0.0 == "Content-Range" }?.1, "bytes 37-613/1000")
        XCTAssertEqual(wide.1.first { $0.0 == "Content-Length" }?.1, "577")
        XCTAssertEqual(reads.current.last, ByteRange(start: 100, end: 613)!)

        // bytes=0- is a 206 covering the whole resource.
        let openFromZero = try await body(router.route(head(path, range: "bytes=0-")))
        XCTAssertEqual(openFromZero.0, 206)
        XCTAssertEqual(openFromZero.2, content)
        XCTAssertEqual(openFromZero.1.first { $0.0 == "Content-Range" }?.1, "bytes 0-999/1000")
        XCTAssertEqual(openFromZero.1.first { $0.0 == "Content-Length" }?.1, "1000")

        // End past totalSize is clamped, and the headers describe what is sent.
        let clamped = try await body(router.route(head(path, range: "bytes=950-5000")))
        XCTAssertEqual(clamped.0, 206)
        XCTAssertEqual(clamped.2, Array(content[950...999]))
        XCTAssertEqual(clamped.1.first { $0.0 == "Content-Range" }?.1, "bytes 950-999/1000")
        XCTAssertEqual(clamped.1.first { $0.0 == "Content-Length" }?.1, "50")

        // Suffix forms, including one larger than the resource.
        let suffix = try await body(router.route(head(path, range: "bytes=-30")))
        XCTAssertEqual(suffix.2, Array(content[970...999]))
        XCTAssertEqual(suffix.1.first { $0.0 == "Content-Range" }?.1, "bytes 970-999/1000")
        let hugeSuffix = try await body(router.route(head(path, range: "bytes=-5000")))
        XCTAssertEqual(hugeSuffix.0, 206)
        XCTAssertEqual(hugeSuffix.2, content)
        XCTAssertEqual(hugeSuffix.1.first { $0.0 == "Content-Range" }?.1, "bytes 0-999/1000")
        let smallSuffix = try await body(router.route(head(path, range: "bytes=-10")))
        XCTAssertEqual(smallSuffix.2, Array(content[990...999]))

        // Full body: 200 with no Content-Range, prefix then read.
        let full = try await body(router.route(head(path)))
        XCTAssertEqual(full.0, 200)
        XCTAssertEqual(full.2, content)
        XCTAssertNil(full.1.first { $0.0 == "Content-Range" })
        XCTAssertEqual(full.1.first { $0.0 == "Content-Length" }?.1, "1000")

        for refusal in ["bytes=1000-", "bytes=1000-1005", "bytes=-0", "bytes=500-100", "bytes=0-1,5-6"] {
            let refused = try await body(router.route(head(path, range: refusal)))
            XCTAssertEqual(refused.0, 416, refusal)
            XCTAssertEqual(refused.1.first { $0.0 == "Content-Range" }?.1, "bytes */1000", refusal)
        }
    }

    func testReadFailureAfterPrefixSurfacesToTheCaller() async throws {
        struct Boom: Error {}
        let media = MediaResource(totalSize: 1000, prefix: [UInt8](repeating: 1, count: 100)) { _ in
            AsyncThrowingStream { $0.finish(throwing: Boom()) }
        }
        let router = PlaybackRouter()
        let token = router.register(PlaybackAssets(playlists: [:], media: ["v.mp4": media]))
        guard case .media(_, _, let stream) = router.route(head("/\(token)/v.mp4", range: "bytes=50-199")) else {
            return XCTFail("expected media")
        }
        var received: [UInt8] = []
        do {
            for try await chunk in stream { received += chunk }
            XCTFail("expected the read error")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertEqual(received, [UInt8](repeating: 1, count: 50))
    }

    func testTokens() {
        let tokens = Set((0..<64).map { _ in PlaybackRouter.makeToken() })
        XCTAssertEqual(tokens.count, 64)
        for token in tokens {
            XCTAssertEqual(token.count, 32)
            XCTAssertTrue(token.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
    }

    func testNoTokenOrExtraSegmentsAre404() async throws {
        let (router, token) = makeRouter(reads: Locked([]))
        for path in ["/", "/master.m3u8", "/\(token)", "/\(token)/", "/\(token)/master.m3u8/extra", "//master.m3u8"] {
            let result = try await body(router.route(head(path)))
            XCTAssertEqual(result.0, 404, path)
        }
        let headRequest = try await body(router.route(head("/\(token)/master.m3u8", method: "HEAD")))
        XCTAssertEqual(headRequest.0, 200)
    }
}
