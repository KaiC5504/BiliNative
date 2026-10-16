import Foundation
import BiliAPI

/// Codec kinds AVPlayer refused on this phone, so they are not tried first again.
final class CodecMemory: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "playback.failedCodecs"
    private let hev1Key = "playback.hev1LabelsHoldHEV1"

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

    func markFailed(_ kind: String) {
        defaults.set(Array(failed.union([kind])).sorted(), forKey: key)
    }

    /// Set once a stream labelled hev1 held a real hev1 sample entry. Direct mode cannot rename one, so it then
    /// skips hev1 labels before fetching anything; until then it reads the bytes, which can be hvc1.
    var hev1LabelsHoldHEV1: Bool { defaults.bool(forKey: hev1Key) }

    func noteHEV1Entry() {
        defaults.set(true, forKey: hev1Key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: hev1Key)
    }
}
