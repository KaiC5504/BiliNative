import BiliShared

/// BTR `createBanList`. A node that twice fails without sending a byte is skipped for the rest of
/// the video. For HTTP 4xx, what has delivered decides who is blamed: a refusal by a node that
/// serves other addresses blames the address; a refusal of an address other nodes serve blames
/// that node and address pair, and the node once it refuses two such addresses.
public final class BanList: @unchecked Sendable {
    public enum BanKind: Equatable, Sendable {
        case node, address, pair
    }

    private struct State {
        var emptyReplies: [String: Int] = [:]
        var goodNodes = Set<String>()
        var goodAddresses = Set<String>()
        var reported = Set<String>()
        var banned = Set<String>()
    }

    private let state = Locked(State())
    private let limit: Int
    private let banHandler = Locked<((_ node: String, _ strikes: Int, _ kind: BanKind) -> Void)?>(nil)

    public var onBan: ((_ node: String, _ strikes: Int, _ kind: BanKind) -> Void)? {
        get { banHandler.current }
        set { banHandler.withLock { $0 = newValue } }
    }

    public init(limit: Int = 2) {
        self.limit = max(1, limit)
    }

    @discardableResult
    public func record(url: String, receivedBytes: Int64, status: Int?) -> Bool {
        guard receivedBytes == 0 else { return false }
        let node = NodeCatalog.nodeKey(of: url)
        guard !node.isEmpty else { return false }
        let refused = status.map { (400..<500).contains($0) } ?? false
        let key = "\(node)\n\(NodeCatalog.address(of: url))\n\(refused ? "refused" : "")"
        let added = state.withLock { value -> [(String, Int)] in
            value.emptyReplies[key, default: 0] += 1
            return judge(&value)
        }
        report(added, url: url)
        return !added.isEmpty
    }

    public func success(url: String) {
        let node = NodeCatalog.nodeKey(of: url)
        let address = NodeCatalog.address(of: url)
        guard !node.isEmpty else { return }
        let added = state.withLock { value -> [(String, Int)] in
            // Deviation from BTR: blip strikes heal on success, so a local network drop cannot ban the fastest nodes for good.
            let silent = value.emptyReplies.keys.filter { $0.hasPrefix("\(node)\n") && $0.hasSuffix("\n") }
            for key in silent { value.emptyReplies[key] = nil }
            if silent.isEmpty && value.goodNodes.contains(node) && value.goodAddresses.contains(address) { return [] }
            value.goodNodes.insert(node)
            value.goodAddresses.insert(address)
            let added = judge(&value)
            if !silent.isEmpty {
                value.reported = value.reported.filter { !$0.hasPrefix("node:") || value.banned.contains($0) }
            }
            return added
        }
        report(added, url: url)
    }

    public func allows(_ url: String) -> Bool {
        let node = NodeCatalog.nodeKey(of: url)
        let address = NodeCatalog.address(of: url)
        return state.withLock {
            !$0.banned.contains("node:\(node)") && !$0.banned.contains("address:\(address)") && !$0.banned.contains("pair:\(node) \(address)")
        }
    }

    public func allowsNode(_ url: String) -> Bool {
        let node = NodeCatalog.nodeKey(of: url)
        return state.withLock { !$0.banned.contains("node:\(node)") }
    }

    public func allowsAddress(_ url: String) -> Bool {
        let address = NodeCatalog.address(of: url)
        return state.withLock { !$0.banned.contains("address:\(address)") }
    }

    public func bannedNodes() -> [String] {
        state.current.banned.filter { $0.hasPrefix("node:") }.map { String($0.dropFirst(5)) }.sorted()
    }

    public func reset() {
        state.withLock { $0 = State() }
    }

    private func judge(_ value: inout State) -> [(String, Int)] {
        let replies = value.emptyReplies.map { key, count in
            let parts = key.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return (node: parts[0], address: parts[1], refused: parts[2] == "refused", count: count)
        }
        // Deviation from BTR: refusing one address that others serve costs a node only that pair, and the
        // node itself once it refuses a second such address. One refused address can be that node's alone
        // (Akamai refusing os=cosovbv but serving os=akam), and a node ban would keep it from ever
        // proving its other addresses, so the ban would never lift.
        var refusedServed: [String: Set<String>] = [:]
        for reply in replies where reply.refused && !value.goodNodes.contains(reply.node) && value.goodAddresses.contains(reply.address) {
            refusedServed[reply.node, default: []].insert(reply.address)
        }
        var strikes: [String: Int] = [:]
        for (node, address, refused, count) in replies {
            let blamed: String
            if !refused {
                blamed = "node:\(node)"
            } else if value.goodNodes.contains(node) {
                blamed = value.goodAddresses.contains(address) ? "pair:\(node) \(address)" : "address:\(address)"
            } else if value.goodAddresses.contains(address) {
                blamed = (refusedServed[node]?.count ?? 0) > 1 ? "node:\(node)" : "pair:\(node) \(address)"
            } else {
                blamed = ""
            }
            if !blamed.isEmpty { strikes[blamed, default: 0] += count }
        }
        value.banned = Set(strikes.filter { $0.value >= limit }.map(\.key))
        var added: [(String, Int)] = []
        for key in value.banned.sorted() where !value.reported.contains(key) {
            value.reported.insert(key)
            added.append((key, strikes[key] ?? 0))
        }
        return added
    }

    private func report(_ added: [(String, Int)], url: String) {
        guard let handler = banHandler.current else { return }
        for (key, strikes) in added {
            if key.hasPrefix("node:") {
                handler(String(key.dropFirst(5)), strikes, .node)
            } else if key.hasPrefix("pair:") {
                // Another node's success can complete a pair ban, so the node comes from the key, not the URL.
                handler(String(key.dropFirst(5).prefix { $0 != " " }), strikes, .pair)
            } else {
                handler(NodeCatalog.nodeKey(of: url), strikes, .address)
            }
        }
    }
}
