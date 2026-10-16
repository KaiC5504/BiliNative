import Foundation

public struct PlayItem: Hashable, Sendable {
    public var bvid: String
    public var cid: Int64

    public init(bvid: String, cid: Int64) {
        self.bvid = bvid
        self.cid = cid
    }
}

public enum LoopMode: String, CaseIterable, Sendable {
    case single, list, none
}

public enum NextStep: Equatable, Sendable {
    case replay
    case play(PlayItem)
    case stop
}

public enum Autoplay {
    /// `episodes` is every 合集 episode of every section, in order. A multi-part video sits in it once, under its first cid,
    /// so a later part is located by bvid when its own cid is not listed.
    public static func next(after current: PlayItem, parts: [PlayItem], episodes: [PlayItem], autoplay: Bool, loop: LoopMode) -> NextStep {
        if loop == .single { return .replay }
        guard autoplay || loop == .list else { return .stop }

        let siblings = parts.filter { $0.bvid == current.bvid }
        if let i = siblings.firstIndex(where: { $0.cid == current.cid }), siblings.indices.contains(i + 1) {
            return .play(siblings[i + 1])
        }

        let position = episodes.firstIndex(where: { $0.cid == current.cid })
            ?? episodes.firstIndex(where: { $0.bvid == current.bvid })
        if let position, episodes.indices.contains(position + 1) {
            return .play(episodes[position + 1])
        }

        guard loop == .list else { return .stop }
        // Looping covers the collection the video belongs to, otherwise just its own parts.
        let first = position != nil ? episodes.first : siblings.first
        guard let first, first != current else { return .replay }
        return .play(first)
    }
}
