import UIKit
import XCTest
@testable import BiliNative

final class ImageLoaderTests: XCTestCase {
    private final class FetchLog: @unchecked Sendable {
        private let lock = NSLock()
        private var fetched: [URL] = []

        func add(_ url: URL) {
            lock.lock()
            fetched.append(url)
            lock.unlock()
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return fetched
        }
    }

    private static func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("image-loader-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeLoader(log: FetchLog, directory: URL) -> ImageLoader {
        let png = Self.pngData()
        return ImageLoader(fetch: { url in
            log.add(url)
            return png
        }, directory: directory)
    }

    func testSecondRequestComesFromCache() async {
        let log = FetchLog()
        let loader = makeLoader(log: log, directory: makeDirectory())
        let url = URL(string: "https://i0.hdslb.com/bfs/archive/cover.png")!
        let first = await loader.image(for: url)
        let second = await loader.image(for: url)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(log.urls.count, 1)
    }

    func testProtocolRelativeURLsBecomeHTTPS() async {
        XCTAssertEqual(ImageLoader.secureURL("//i0.hdslb.com/a.png")?.absoluteString, "https://i0.hdslb.com/a.png")
        XCTAssertEqual(ImageLoader.secureURL("http://i0.hdslb.com/a.png")?.absoluteString, "https://i0.hdslb.com/a.png")
        XCTAssertEqual(ImageLoader.secureURL("https://i0.hdslb.com/a.png")?.absoluteString, "https://i0.hdslb.com/a.png")

        let log = FetchLog()
        let loader = makeLoader(log: log, directory: makeDirectory())
        _ = await loader.image(for: URL(string: "//i0.hdslb.com/b.png")!)
        _ = await loader.image(for: URL(string: "http://i0.hdslb.com/c.png")!)
        XCTAssertEqual(log.urls.map(\.absoluteString), ["https://i0.hdslb.com/b.png", "https://i0.hdslb.com/c.png"])
    }

    func testDiskCacheServesALaterLoader() async {
        let log = FetchLog()
        let directory = makeDirectory()
        let url = URL(string: "https://i0.hdslb.com/bfs/face/avatar.png")!
        _ = await makeLoader(log: log, directory: directory).image(for: url)
        let later = await makeLoader(log: log, directory: directory).image(for: url)
        XCTAssertNotNil(later)
        XCTAssertEqual(log.urls.count, 1)
    }

    func testTwoAtOnceShareOneFetch() async {
        let log = FetchLog()
        let loader = makeLoader(log: log, directory: makeDirectory())
        let url = URL(string: "https://i0.hdslb.com/bfs/archive/shared.png")!
        async let a = loader.image(for: url)
        async let b = loader.image(for: url)
        let images = await [a, b]
        XCTAssertEqual(images.compactMap { $0 }.count, 2)
        XCTAssertEqual(log.urls.count, 1)
    }

    func testFailedFetchGivesNilAndIsNotCached() async {
        let log = FetchLog()
        let loader = ImageLoader(fetch: { url in
            log.add(url)
            throw URLError(.notConnectedToInternet)
        }, directory: makeDirectory())
        let url = URL(string: "https://i0.hdslb.com/bfs/archive/missing.png")!
        let first = await loader.image(for: url)
        _ = await loader.image(for: url)
        XCTAssertNil(first)
        XCTAssertEqual(log.urls.count, 2)
    }
}
