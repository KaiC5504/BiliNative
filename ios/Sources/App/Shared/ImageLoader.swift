import CryptoKit
import UIKit
import BiliAPI
import DevLog

/// Memory and disk cache for remote images, keyed by the https form of the URL.
actor ImageLoader {
    static let shared: ImageLoader = {
        #if DEBUG
        if DemoFixtures.isEnabled { return ImageLoader(fetch: { try await DemoFixtures.image(for: $0) }) }
        #endif
        return ImageLoader()
    }()

    static let network: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url)
        for (name, value) in BiliClient.mediaHeaders { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images", isDirectory: true)
    }

    private let fetch: @Sendable (URL) async throws -> Data
    private let directory: URL
    private let memory = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]

    init(fetch: @escaping @Sendable (URL) async throws -> Data = ImageLoader.network, directory: URL = ImageLoader.defaultDirectory) {
        self.fetch = fetch
        self.directory = directory
        memory.totalCostLimit = 64 * 1024 * 1024
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Bilibili's JSON hands out `//host/path` and `http://` addresses; App Transport Security wants https.
    static func secureURL(_ string: String) -> URL? {
        if string.hasPrefix("//") { return URL(string: "https:" + string) }
        if string.hasPrefix("http://") { return URL(string: "https://" + string.dropFirst("http://".count)) }
        return URL(string: string)
    }

    func image(for url: URL) async -> UIImage? {
        let secure = Self.secureURL(url.absoluteString) ?? url
        let key = Self.cacheKey(secure)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = loading[key] { return await running.value }
        let task = Task { await self.load(secure, key: key) }
        loading[key] = task
        return await task.value
    }

    private func load(_ url: URL, key: String) async -> UIImage? {
        defer { loading[key] = nil }
        let file = directory.appendingPathComponent(key)
        if let stored = try? Data(contentsOf: file) {
            if let image = await Self.decode(stored) {
                remember(image, key: key)
                return image
            }
            try? FileManager.default.removeItem(at: file)
        }
        do {
            let data = try await fetch(url)
            guard let image = await Self.decode(data) else { return nil }
            try? data.write(to: file, options: .atomic)
            remember(image, key: key)
            return image
        } catch {
            if !(error is CancellationError) {
                Logger.shared.warn(.app, "image fetch failed", ["host": .init(url.host ?? ""), "error": .init(String(describing: error))])
            }
            return nil
        }
    }

    private func remember(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Decoded here so the first draw does not decode on the main thread.
    private static func decode(_ data: Data) async -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }

    private static func cacheKey(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
