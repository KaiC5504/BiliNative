import Foundation
import BiliShared

public struct MediaResource: Sendable {
    public let totalSize: Int64
    /// Served from memory: the (patched) init segment and index.
    public let prefix: [UInt8]
    public let read: @Sendable (ByteRange) -> AsyncThrowingStream<[UInt8], Error>

    public init(totalSize: Int64, prefix: [UInt8], read: @escaping @Sendable (ByteRange) -> AsyncThrowingStream<[UInt8], Error>) {
        self.totalSize = totalSize
        self.prefix = prefix
        self.read = read
    }
}

public struct PlaybackAssets: Sendable {
    public var playlists: [String: String]
    public var media: [String: MediaResource]

    public init(playlists: [String: String], media: [String: MediaResource]) {
        self.playlists = playlists
        self.media = media
    }
}

public enum PlaybackBodyError: Error, Equatable {
    case shorter(expected: Int64, received: Int64)
    case longer(expected: Int64)
}

public enum RouteResult {
    case text(status: Int, contentType: String, body: [UInt8])
    case media(status: Int, headers: [(String, String)], body: AsyncThrowingStream<[UInt8], Error>)
    case failure(status: Int, headers: [(String, String)])
}

public final class PlaybackRouter: @unchecked Sendable {
    private let entries = Locked<[String: PlaybackAssets]>([:])

    public init() {}

    /// 128 random bits as hex: the server listens on localhost only, and the token keeps other
    /// processes from guessing a playback's paths.
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<4).map { _ in
            let hex = String(UInt32.random(in: .min ... .max, using: &generator), radix: 16)
            return String(repeating: "0", count: 8 - hex.count) + hex
        }.joined()
    }

    @discardableResult
    public func register(_ assets: PlaybackAssets, token: String = PlaybackRouter.makeToken()) -> String {
        entries.withLock { $0[token] = assets }
        return token
    }

    public func unregister(_ token: String) {
        entries.withLock { $0[token] = nil }
    }

    public func route(_ head: HTTPRequestHead) -> RouteResult {
        guard head.method == "GET" || head.method == "HEAD" else { return .failure(status: 405, headers: []) }
        let parts = head.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0].isEmpty, let assets = entries.current[parts[1]] else { return .failure(status: 404, headers: []) }
        if let playlist = assets.playlists[parts[2]] {
            return .text(status: 200, contentType: "application/vnd.apple.mpegurl", body: Array(playlist.utf8))
        }
        guard let media = assets.media[parts[2]] else { return .failure(status: 404, headers: []) }
        let status: Int
        let range: ByteRange
        switch RangeRequest.parse(head.headers["range"], totalSize: media.totalSize) {
        case .unsatisfiable:
            return .failure(status: 416, headers: [("Content-Range", "bytes */\(media.totalSize)")])
        case .full:
            guard let whole = ByteRange(start: 0, end: media.totalSize - 1) else { return .failure(status: 416, headers: []) }
            status = 200
            range = whole
        case .range(let requested):
            status = 206
            range = requested
        }
        var headers = [("Content-Type", "video/mp4"), ("Accept-Ranges", "bytes"), ("Content-Length", "\(range.length)")]
        if status == 206 { headers.append(("Content-Range", "bytes \(range.start)-\(range.end)/\(media.totalSize)")) }
        if head.method == "HEAD" {
            return .media(status: status, headers: headers, body: AsyncThrowingStream { $0.finish() })
        }
        return .media(status: status, headers: headers, body: Self.body(media, range))
    }

    /// Fails the stream unless it delivers exactly `expected` bytes, so a short or long upstream
    /// cannot leave a client waiting on an advertised Content-Length.
    static func lengthChecked(_ stream: AsyncThrowingStream<[UInt8], Error>, expected: Int64) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var received: Int64 = 0
                do {
                    for try await chunk in stream {
                        let remaining = expected - received
                        if Int64(chunk.count) > remaining {
                            if remaining > 0 { continuation.yield(Array(chunk[0..<Int(remaining)])) }
                            continuation.finish(throwing: PlaybackBodyError.longer(expected: expected))
                            return
                        }
                        received += Int64(chunk.count)
                        continuation.yield(chunk)
                    }
                    if received == expected {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: PlaybackBodyError.shorter(expected: expected, received: received))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func body(_ media: MediaResource, _ range: ByteRange) -> AsyncThrowingStream<[UInt8], Error> {
        let prefixEnd = Int64(media.prefix.count) - 1
        if range.end <= prefixEnd {
            let bytes = Array(media.prefix[Int(range.start)...Int(range.end)])
            return AsyncThrowingStream { continuation in
                continuation.yield(bytes)
                continuation.finish()
            }
        }
        if range.start > prefixEnd { return lengthChecked(media.read(range), expected: range.length) }
        let head = Array(media.prefix[Int(range.start)...Int(prefixEnd)])
        guard let rest = ByteRange(start: prefixEnd + 1, end: range.end) else {
            return lengthChecked(media.read(range), expected: range.length)
        }
        let tail = lengthChecked(media.read(rest), expected: rest.length)
        return AsyncThrowingStream { continuation in
            continuation.yield(head)
            let task = Task {
                do {
                    for try await chunk in tail { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
