import AVFoundation
import BiliShared

/// Direct mode hands AVPlayer its playlists through a custom URL scheme instead of the local
/// server, so it still works when the server is what failed. Media URIs inside are the CDN's.
final class DirectPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "bilinative"
    let queue = DispatchQueue(label: "bilinative.direct-loader")
    private let entries = Locked<[String: [String: String]]>([:])

    func register(token: String, playlists: [String: String]) -> URL {
        entries.withLock { $0[token] = playlists }
        return URL(string: "\(Self.scheme)://\(token)/master.m3u8")!
    }

    func unregister(_ token: String) {
        entries.withLock { $0[token] = nil }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.scheme, let token = url.host,
              let text = entries.current[token]?[url.lastPathComponent] else { return false }
        loadingRequest.dataRequest?.respond(with: Data(text.utf8))
        loadingRequest.finishLoading()
        return true
    }
}
