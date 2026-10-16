#if DEBUG
import Foundation

/// `-DemoPanel quality|codec|speed|more|episodes` opens the video page with that panel showing. The page turns to
/// landscape first, unless `-DemoPortrait YES` asks for the bottom sheet.
enum DemoPanel {
    static var requested: PlayerPanel? {
        switch UserDefaults.standard.string(forKey: "DemoPanel") {
        case "quality": .quality
        case "codec": .codec
        case "speed": .speed
        case "more": .more
        case "episodes": .episodes
        default: nil
        }
    }

    static var landscape: Bool { !UserDefaults.standard.bool(forKey: "DemoPortrait") }
}
#endif
