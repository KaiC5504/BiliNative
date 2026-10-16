import Foundation
import BiliAPI

/// Codec kinds AVPlayer refused on this phone, so they are not tried first again.
final class CodecMemory: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "playback.failedCodecs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var failed: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    var failedKinds: Set<String> { failed }

    func order(preferred: VideoCodec) -> [VideoCodec] {
        let fallback: [VideoCodec] = [.hevc, .av1, .avc]
        let order = [preferred] + fallback.filter { $0 != preferred }
        return order.filter { !failed.contains($0.rawValue) }
    }

    var excludesDolby: Bool { failed.contains("dolby") }

    func markFailed(_ kind: String) {
        defaults.set(Array(failed.union([kind])).sorted(), forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
