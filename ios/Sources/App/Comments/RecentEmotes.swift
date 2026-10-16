import Foundation
import BiliAPI

/// The emote panel's 最近使用, kept on the phone: most recent first, one entry per token.
enum RecentEmotes {
    static let key = "emotes.recent"
    static let limit = 14

    private struct Stored: Codable {
        var token: String
        var url: String
        var large: Bool
    }

    static func list(defaults: UserDefaults = .standard) -> [Emote] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return stored.map { Emote(token: $0.token, url: $0.url, large: $0.large) }
    }

    static func record(_ emote: Emote, defaults: UserDefaults = .standard) {
        var emotes = list(defaults: defaults).filter { $0.token != emote.token }
        emotes.insert(emote, at: 0)
        let stored = emotes.prefix(limit).map { Stored(token: $0.token, url: $0.url, large: $0.large) }
        if let data = try? JSONEncoder().encode(Array(stored)) {
            defaults.set(data, forKey: key)
        }
    }
}
