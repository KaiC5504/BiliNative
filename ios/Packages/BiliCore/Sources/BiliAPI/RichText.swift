import Foundation

public enum RichRun: Equatable, Sendable {
    case text(String)
    case emote(token: String, url: String, size: Int)
    case mention(name: String, mid: Int64)
    case link(title: String, url: String)
    case video(id: String)
    case timestamp(label: String, seconds: Int)
}

public struct EmoteRef: Equatable, Sendable {
    public var url: String
    public var size: Int

    public init(url: String, size: Int) {
        self.url = url
        self.size = size
    }
}

public struct LinkRef: Equatable, Sendable {
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// Turns a comment's plain text plus the lookup tables the server sends with it into styled runs.
/// Everything works on `Character` boundaries, so an emoji or a combining mark is never cut in half.
public enum RichText {
    private enum Piece {
        case pending([Character])
        case done(RichRun)
    }

    private struct Token {
        let text: String
        let characters: [Character]
        let run: RichRun
    }

    private typealias Matcher = ([Character], Int) -> (length: Int, run: RichRun)?

    /// Each kind is searched in the text the earlier kinds left over, so an emote key wins over a mention,
    /// a mention over a link, and a link key over a bare BV number inside it.
    public static func runs(_ message: String, emotes: [String: EmoteRef], mentions: [String: Int64],
                            links: [String: LinkRef]) -> [RichRun] {
        var pieces = [Piece.pending(Array(message))]
        pieces = split(pieces, with: literals(emotes.map { key, ref in
            (key, RichRun.emote(token: key, url: ref.url, size: ref.size))
        }, once: false))
        pieces = split(pieces, with: literals(mentions.map { name, mid in
            ("@" + name, RichRun.mention(name: name, mid: mid))
        }, once: false))
        // The server marks these `match_once`: only the first occurrence of a link word is a link.
        pieces = split(pieces, with: literals(links.map { key, ref in
            (key, RichRun.link(title: ref.title, url: ref.url))
        }, once: true))
        pieces = split(pieces, with: videoID)
        pieces = split(pieces, with: timestamp)
        return merged(pieces)
    }

    private static func split(_ pieces: [Piece], with match: Matcher) -> [Piece] {
        var output: [Piece] = []
        for piece in pieces {
            guard case .pending(let characters) = piece else {
                output.append(piece)
                continue
            }
            var start = 0
            var index = 0
            while index < characters.count {
                if let (length, run) = match(characters, index) {
                    if start < index { output.append(.pending(Array(characters[start..<index]))) }
                    output.append(.done(run))
                    index += length
                    start = index
                } else {
                    index += 1
                }
            }
            if start < characters.count { output.append(.pending(Array(characters[start...]))) }
        }
        return output
    }

    private static func merged(_ pieces: [Piece]) -> [RichRun] {
        var runs: [RichRun] = []
        var buffer = ""
        for piece in pieces {
            switch piece {
            case .pending(let characters):
                buffer += String(characters)
            case .done(let run):
                if !buffer.isEmpty { runs.append(.text(buffer)) }
                buffer = ""
                runs.append(run)
            }
        }
        if !buffer.isEmpty { runs.append(.text(buffer)) }
        return runs
    }

    /// Longest token first, so "@小明明" is not read as "@小明" followed by "明".
    private static func literals(_ entries: [(token: String, run: RichRun)], once: Bool) -> Matcher {
        var tokens: [Token] = []
        for entry in entries where !entry.token.isEmpty {
            tokens.append(Token(text: entry.token, characters: Array(entry.token), run: entry.run))
        }
        tokens.sort { lhs, rhs in
            if lhs.characters.count != rhs.characters.count { return lhs.characters.count > rhs.characters.count }
            return lhs.text < rhs.text
        }
        var used = Set<Int>()
        return { characters, index in
            for (position, token) in tokens.enumerated() where !(once && used.contains(position)) {
                if matches(characters, at: index, token.characters) {
                    used.insert(position)
                    return (token.characters.count, token.run)
                }
            }
            return nil
        }
    }

    private static func matches(_ characters: [Character], at index: Int, _ token: [Character]) -> Bool {
        guard index + token.count <= characters.count else { return false }
        for offset in token.indices where characters[index + offset] != token[offset] { return false }
        return true
    }

    /// `BV` plus ten letters or digits, or `av` plus digits.
    private static func videoID(_ characters: [Character], _ index: Int) -> (length: Int, run: RichRun)? {
        if matches(characters, at: index, ["B", "V"]) {
            let end = index + 12
            guard end <= characters.count, characters[(index + 2)..<end].allSatisfy(isASCIIAlphanumeric) else { return nil }
            return (12, .video(id: String(characters[index..<end])))
        }
        if matches(characters, at: index, ["a", "v"]) {
            let end = endOfDigits(characters, from: index + 2)
            guard end > index + 2 else { return nil }
            return (end - index, .video(id: String(characters[index..<end])))
        }
        return nil
    }

    /// `m:ss` or `h:mm:ss` with either colon. A digit on either side means the number is something else,
    /// such as the "1920:1080" in a resolution, so it is left as text.
    private static func timestamp(_ characters: [Character], _ index: Int) -> (length: Int, run: RichRun)? {
        if index > 0, isASCIIDigit(characters[index - 1]) { return nil }
        let leadEnd = endOfDigits(characters, from: index)
        guard (1...2).contains(leadEnd - index), isColon(characters, at: leadEnd), twoDigits(characters, at: leadEnd + 1) else {
            return nil
        }
        var end = leadEnd + 3
        var fields = [number(characters, index, leadEnd), number(characters, leadEnd + 1, end)]
        if isColon(characters, at: end), twoDigits(characters, at: end + 1), !isDigit(characters, at: end + 3) {
            fields.append(number(characters, end + 1, end + 3))
            end += 3
        }
        guard !isDigit(characters, at: end) else { return nil }
        let seconds = fields.reduce(0) { $0 * 60 + $1 }
        return (end - index, .timestamp(label: String(characters[index..<end]), seconds: seconds))
    }

    private static func number(_ characters: [Character], _ from: Int, _ to: Int) -> Int {
        Int(String(characters[from..<to])) ?? 0
    }

    private static func endOfDigits(_ characters: [Character], from index: Int) -> Int {
        var end = index
        while isDigit(characters, at: end) { end += 1 }
        return end
    }

    private static func twoDigits(_ characters: [Character], at index: Int) -> Bool {
        isDigit(characters, at: index) && isDigit(characters, at: index + 1)
    }

    private static func isDigit(_ characters: [Character], at index: Int) -> Bool {
        index < characters.count && isASCIIDigit(characters[index])
    }

    private static func isColon(_ characters: [Character], at index: Int) -> Bool {
        index < characters.count && (characters[index] == ":" || characters[index] == "：")
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return (48...57).contains(value)
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }
}
