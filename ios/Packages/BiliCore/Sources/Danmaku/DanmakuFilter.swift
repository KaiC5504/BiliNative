import Foundation

public struct BlockRule: Sendable, Hashable {
    public enum Kind: Int, Sendable {
        case keyword = 0
        case regex = 1
        case user = 2
    }

    public var id: Int64
    public var kind: Kind
    public var filter: String

    public init(id: Int64, kind: Kind, filter: String) {
        self.id = id
        self.kind = kind
        self.filter = filter
    }
}

public struct DanmakuFilterOptions: Sendable, Equatable, Codable {
    public var blockFixed: Bool
    public var blockScroll: Bool
    public var blockColored: Bool
    /// Mode 7 is dropped whatever this says; kept so the settings panel has its switch.
    public var blockAdvanced: Bool
    /// Hides the danmaku that dedupe would show as "×N".
    public var blockCount: Bool
    public var dedupe: Bool
    public var hideBottom: Bool
    public var applyRules: Bool

    public init(blockFixed: Bool = false, blockScroll: Bool = false, blockColored: Bool = false,
                blockAdvanced: Bool = false, blockCount: Bool = false, dedupe: Bool = false,
                hideBottom: Bool = false, applyRules: Bool = true) {
        self.blockFixed = blockFixed
        self.blockScroll = blockScroll
        self.blockColored = blockColored
        self.blockAdvanced = blockAdvanced
        self.blockCount = blockCount
        self.dedupe = dedupe
        self.hideBottom = hideBottom
        self.applyRules = applyRules
    }

    /// Settings saved by an older build lack newer keys; they take the defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(blockFixed: try c.decodeIfPresent(Bool.self, forKey: .blockFixed) ?? false,
                  blockScroll: try c.decodeIfPresent(Bool.self, forKey: .blockScroll) ?? false,
                  blockColored: try c.decodeIfPresent(Bool.self, forKey: .blockColored) ?? false,
                  blockAdvanced: try c.decodeIfPresent(Bool.self, forKey: .blockAdvanced) ?? false,
                  blockCount: try c.decodeIfPresent(Bool.self, forKey: .blockCount) ?? false,
                  dedupe: try c.decodeIfPresent(Bool.self, forKey: .dedupe) ?? false,
                  hideBottom: try c.decodeIfPresent(Bool.self, forKey: .hideBottom) ?? false,
                  applyRules: try c.decodeIfPresent(Bool.self, forKey: .applyRules) ?? true)
    }
}

public struct DisplayDanmaku: Sendable, Equatable {
    public var elem: DanmakuElem
    public var text: String
    public var isOwn: Bool

    public init(elem: DanmakuElem, text: String, isOwn: Bool) {
        self.elem = elem
        self.text = text
        self.isOwn = isOwn
    }
}

public enum DanmakuFilter {
    private static let mergeWindowMs: Int64 = 10_000

    public static func apply(_ elems: [DanmakuElem], options: DanmakuFilterOptions, rules: [BlockRule], ownHash: String?) -> [DisplayDanmaku] {
        let own = (ownHash?.isEmpty ?? true) ? nil : ownHash
        let matcher = options.applyRules && !rules.isEmpty ? RuleMatcher(rules) : nil

        var passed: [(elem: DanmakuElem, isOwn: Bool)] = []
        passed.reserveCapacity(elems.count)
        for elem in elems {
            if (7...9).contains(elem.mode) { continue }
            if typeBlocked(elem, options) { continue }
            let isOwn = own != nil && elem.midHash == own
            if !isOwn, let matcher, matcher.blocks(elem) { continue }
            passed.append((elem, isOwn))
        }

        if !isSorted(passed.map(\.elem.progressMs)) {
            passed = passed.enumerated()
                .sorted { ($0.element.elem.progressMs, $0.offset) < ($1.element.elem.progressMs, $1.offset) }
                .map(\.element)
        }

        guard options.dedupe || options.blockCount else {
            return passed.map { DisplayDanmaku(elem: $0.elem, text: $0.elem.content, isOwn: $0.isOwn) }
        }
        return merged(passed, dropMerged: options.blockCount)
    }

    private static func typeBlocked(_ elem: DanmakuElem, _ options: DanmakuFilterOptions) -> Bool {
        switch elem.mode {
        case 1, 6: if options.blockScroll { return true }
        case 4: if options.blockFixed || options.hideBottom { return true }
        case 5: if options.blockFixed { return true }
        default: break
        }
        return options.blockColored && (elem.color != 0xFFFFFF || elem.colorful != 0)
    }

    private static func isSorted(_ values: [Int64]) -> Bool {
        var previous = Int64.min
        for value in values {
            if value < previous { return false }
            previous = value
        }
        return true
    }

    /// Own danmaku are never merged away, so the sender always sees theirs.
    private static func merged(_ items: [(elem: DanmakuElem, isOwn: Bool)], dropMerged: Bool) -> [DisplayDanmaku] {
        var groups: [(elem: DanmakuElem, isOwn: Bool, count: Int)] = []
        var lastKept: [String: Int] = [:]
        for item in items {
            if !item.isOwn, let index = lastKept[item.elem.content],
               item.elem.progressMs - groups[index].elem.progressMs <= mergeWindowMs {
                groups[index].count += 1
                continue
            }
            if !item.isOwn { lastKept[item.elem.content] = groups.count }
            groups.append((item.elem, item.isOwn, 1))
        }
        var result: [DisplayDanmaku] = []
        result.reserveCapacity(groups.count)
        for group in groups {
            if group.count >= 2 && dropMerged { continue }
            let text = group.count >= 2 ? "\(group.elem.content) ×\(group.count)" : group.elem.content
            result.append(DisplayDanmaku(elem: group.elem, text: text, isOwn: group.isOwn))
        }
        return result
    }
}

private struct RuleMatcher {
    private var keywords: [String] = []
    private var regexes: [NSRegularExpression] = []
    private var users: Set<String> = []

    init(_ rules: [BlockRule]) {
        for rule in rules where !rule.filter.isEmpty {
            switch rule.kind {
            case .keyword:
                keywords.append(rule.filter)
            case .regex:
                var pattern = rule.filter
                if pattern.count >= 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
                    pattern = String(pattern.dropFirst().dropLast())
                }
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    regexes.append(regex)
                }
            case .user:
                users.insert(rule.filter)
            }
        }
    }

    func blocks(_ elem: DanmakuElem) -> Bool {
        if !users.isEmpty, users.contains(elem.midHash) { return true }
        for keyword in keywords where elem.content.contains(keyword) { return true }
        if !regexes.isEmpty {
            let content = elem.content
            let range = NSRange(location: 0, length: content.utf16.count)
            for regex in regexes where regex.firstMatch(in: content, options: [], range: range) != nil { return true }
        }
        return false
    }
}
