import Foundation
import Danmaku

/// The 弹幕设置 panel's values, kept for every video.
struct DanmakuSettings: Codable, Equatable {
    static let areas: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]
    /// Seconds a scrolling danmaku takes to cross the screen, 极慢 to 极快.
    static let scrollDurations: [Double] = [11, 9, 7, 5.5, 4]
    static let defaults = DanmakuSettings()

    var enabled = true
    /// Share of the video's height the lanes may use.
    var area = 0.5
    var opacity = 1.0
    var scale = 1.0
    /// Index into `scrollDurations`.
    var speed = 2
    var filter = DanmakuFilterOptions()

    var scrollDuration: Double {
        Self.scrollDurations[min(max(speed, 0), Self.scrollDurations.count - 1)]
    }

    init() {}

    /// Settings saved by an older build lack newer keys; they take the defaults instead of failing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DanmakuSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        area = try c.decodeIfPresent(Double.self, forKey: .area) ?? fallback.area
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? fallback.scale
        speed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? fallback.speed
        filter = try c.decodeIfPresent(DanmakuFilterOptions.self, forKey: .filter) ?? fallback.filter
    }
}
