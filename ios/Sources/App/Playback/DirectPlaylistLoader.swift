import AVFoundation
import UniformTypeIdentifiers
import BiliShared

/// Direct mode hands AVPlayer its playlists through a custom URL scheme instead of the local
/// server, so it still works when the server is what failed. Media URIs inside are the CDN's.
final class DirectPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "bilinative"
    let queue = DispatchQueue(label: "bilinative.direct-loader")
    private let entries = Locked<[String: [String: String]]>([:])

    /// bilinative://playlist/<token>/<name>. The token lives in the path because hosts are case-folded.
    static func url(token: String, name: String) -> URL {
        URL(string: "\(scheme)://playlist")!.appendingPathComponent(token).appendingPathComponent(name)
    }

    func register(token: String, playlists: [String: String]) -> URL {
        entries.withLock { $0[token] = playlists }
        return Self.url(token: token, name: "master.m3u8")
    }

    func unregister(_ token: String) {
        entries.withLock { $0[token] = nil }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.scheme else { return false }
        let parts = url.pathComponents
        guard parts.count == 3, let text = entries.current[parts[1]]?[parts[2]] else { return false }
        let data = Data(text.utf8)
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType.m3uPlaylist.identifier
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
        return true
    }
}
