import Foundation
import Danmaku

// TEMPORARY: stands in for Task 12's DanmakuSettings until its branch lands. Deleted before the merge.
struct DanmakuSettings: Codable, Equatable {
    var enabled = true
    var area = 0.5
    var opacity = 1.0
    var scale = 1.0
    var speed = 2
    var filter = DanmakuFilterOptions()
    static let defaults = DanmakuSettings()
}

extension AppSettings {
    var danmaku: DanmakuSettings {
        get {
            UserDefaults.standard.data(forKey: "danmaku.settings.stub").flatMap { try? JSONDecoder().decode(DanmakuSettings.self, from: $0) }
                ?? .defaults
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "danmaku.settings.stub") }
    }
}
