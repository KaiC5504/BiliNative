import Foundation
import BiliShared

/// BTR `createResolver`, one per track. All methods are thread-safe.
public final class Resolver: @unchecked Sendable {
    public struct NodeStatus: Equatable, Sendable {
        public let node: String
        public let state: String
        public let bps: Double
    }

    struct Health {
        var failures = 0
        var blockedUntil: Double = 0
        var lastSuccessAt: Double = 0
    }

    /// Speed knowledge per node and file, without the query: a fresh signature is the same route.
    struct Route {
        var lastSuccessAt: Double = 0
        var lastMeasuredAt: Double = 0
        var bps: Double = 0
    }

    struct State {
        var primary: String
        var backups: [String]
        var health: [String: Health] = [:]
        var routes: [String: Route] = [:]
        var cursor = 0
        var mediaRangeCount = 0
        var rangeCursor = 0
    }

    /// A node left out for being slow goes back to the untested ones after this and gets another try.
    static let measurementTTL: Double = 90_000

    private let state: Locked<State>
    public let mode: NodeMode
    private let policy: MediaURLPolicy
    public let bans: BanList?
    private let clock: MonotonicClock

    public init(primary: String, backups: [String], mode: NodeMode, policy: MediaURLPolicy = .bilibili,
                bans: BanList? = nil, clock: MonotonicClock = .system) {
        state = Locked(State(primary: primary, backups: backups))
        self.mode = mode
        self.policy = policy
        self.bans = bans
        self.clock = clock
    }

    public func replaceURLs(primary: String, backups: [String]) {
        state.withLock {
            $0.primary = primary
            $0.backups = backups
        }
    }

    public func allURLs() -> [String] {
        let value = state.current
        return NodeCatalog.representationURLs(primary: value.primary, backups: value.backups, mode: mode, policy: policy)
    }

    /// Banned addresses are left out, unless that would leave none at all.
    public func urls() -> [String] {
        unbanned(allURLs())
    }

    public func allows(_ url: String) -> Bool {
        bans?.allows(url) ?? true
    }

    private func unbanned(_ list: [String]) -> [String] {
        guard let bans else { return list }
        let allowed = list.filter(bans.allows)
        return allowed.isEmpty ? list : allowed
    }

    static func routeKey(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return url }
        return NodeCatalog.nodeKey(of: url) + components.percentEncodedPath
    }

    private static func measuredNow(_ value: State, _ url: String, _ now: Double) -> Bool {
        guard let route = value.routes[routeKey(url)], route.lastMeasuredAt > 0 else { return false }
        return now - route.lastMeasuredAt < measurementTTL
    }

    private static func fasterFirst(_ value: State) -> (String, String) -> Bool {
        { left, right in
            let l = value.routes[routeKey(left)]
            let r = value.routes[routeKey(right)]
            let lProven = (l?.lastSuccessAt ?? 0) > 0
            let rProven = (r?.lastSuccessAt ?? 0) > 0
            if lProven != rProven { return lProven }
            return (l?.bps ?? 0) > (r?.bps ?? 0)
        }
    }

    public func ordered(pieceIndex: Int = 0, excluding: Set<String> = []) -> [String] {
        let list = urls().filter { !excluding.contains($0) }
        let now = clock.nowMs()
        return state.withLock { value in
            let available = list.filter { (value.health[$0]?.blockedUntil ?? 0) <= now }
            let pool = available.isEmpty ? list : available
            guard !pool.isEmpty else { return [] }
            let offset = (value.cursor + pieceIndex) % pool.count
            value.cursor = (value.cursor + 1) % pool.count
            return Array(pool[offset...] + pool[..<offset])
        }
    }

    /// The nodes for one media range. The first ranges (four overseas, one mainland) go wide to
    /// measure; afterwards measured nodes carry the work, fastest first, and one unmeasured or
    /// stale node rides along per range as exploration.
    public func rangeCandidates() -> [String] {
        let list = urls()
        let now = clock.nowMs()
        let warmup = mode == .mainland ? 1 : 4
        return state.withLock { value in
            let pool = list.filter { (value.health[$0]?.blockedUntil ?? 0) <= now }.sorted(by: Self.fasterFirst(value))
            guard !pool.isEmpty else { return list }
            let width = min(value.mediaRangeCount == 0 ? pool.count : 6, pool.count)
            var selected: [String]
            if value.mediaRangeCount < warmup {
                selected = Array(pool.prefix(width))
                value.rangeCursor = width % pool.count
            } else {
                let measured = pool.filter { Self.measuredNow(value, $0, now) }
                let rest = pool.filter { !Self.measuredNow(value, $0, now) }
                let places = min(rest.count, max(1, width - measured.count))
                let explore = (0..<places).map { rest[(value.rangeCursor + $0) % rest.count] }
                value.rangeCursor = (value.rangeCursor + places) % max(1, pool.count)
                selected = Array(measured.prefix(max(0, width - explore.count))) + explore
                for url in pool {
                    if selected.count >= min(3, pool.count) { break }
                    if !selected.contains(url) { selected.append(url) }
                }
            }
            value.mediaRangeCount += 1
            return selected
        }
    }

    /// The first request of a track races Bilibili's own addresses too (not in custom mode).
    public func startupCandidates() -> [String] {
        let value = state.current
        let now = clock.nowMs()
        var originals: [String] = []
        if case .custom = mode {} else {
            originals = ([value.primary] + value.backups).filter { URL(string: $0).map(policy.allowsURL) ?? false }
        }
        let candidates = unbanned(NodeCatalog.deduplicated(originals + allURLs()))
        return Array(candidates.filter { (value.health[$0]?.blockedUntil ?? 0) <= now }.prefix(8))
    }

    public func rescueCandidates() -> [String] {
        let list = urls()
        let now = clock.nowMs()
        let value = state.current
        return list.filter { (value.health[$0]?.blockedUntil ?? 0) <= now }.sorted(by: Self.fasterFirst(value))
    }

    public func success(_ url: String, bps: Double) {
        bans?.success(url: url)
        let now = clock.nowMs()
        state.withLock { value in
            let key = Self.routeKey(url)
            let old = value.routes[key] ?? Route()
            value.health[url] = Health(failures: 0, blockedUntil: 0, lastSuccessAt: now)
            let measured = bps > 0
            value.routes[key] = Route(
                lastSuccessAt: now,
                lastMeasuredAt: measured ? now : old.lastMeasuredAt,
                bps: !measured ? old.bps : (old.bps > 0 ? old.bps * 0.65 + bps * 0.35 : bps)
            )
        }
    }

    /// The speed of a transfer cut off before its end (it lost a race): the node's speed, not proof
    /// that the address works.
    public func sample(_ url: String, bps: Double) {
        guard bps > 0 else { return }
        let now = clock.nowMs()
        state.withLock { value in
            let key = Self.routeKey(url)
            let old = value.routes[key] ?? Route()
            value.routes[key] = Route(lastSuccessAt: old.lastSuccessAt, lastMeasuredAt: now,
                                      bps: old.bps > 0 ? old.bps * 0.65 + bps * 0.35 : bps)
        }
    }

    public func failure(_ url: String, status: Int?, receivedBytes: Int64) {
        bans?.record(url: url, receivedBytes: receivedBytes, status: status)
        let now = clock.nowMs()
        state.withLock { value in
            var health = value.health[url] ?? Health()
            health.failures += 1
            health.blockedUntil = now + min(60_000, 3_000 * pow(2, Double(min(health.failures, 4))))
            value.health[url] = health
        }
    }

    /// Measured bytes per second of one connection to this node, 0 when unknown or stale.
    public func speed(_ url: String) -> Double {
        let now = clock.nowMs()
        return state.withLock { value in
            Self.measuredNow(value, url, now) ? (value.routes[Self.routeKey(url)]?.bps ?? 0) : 0
        }
    }

    public func status() -> [NodeStatus] {
        let all = allURLs()
        let usable = bans.map { bans in all.filter(bans.allowsAddress) } ?? all
        let list = usable.isEmpty ? all : usable
        let bannedNodes = Set(list.filter { !(bans?.allowsNode($0) ?? true) })
        let now = clock.nowMs()
        let value = state.current
        return list.map { url in
            let route = value.routes[Self.routeKey(url)]
            let state: String
            if bannedNodes.contains(url) {
                state = "banned"
            } else if (value.health[url]?.blockedUntil ?? 0) > now {
                state = "blocked"
            } else if (route?.lastSuccessAt ?? 0) > 0 {
                state = "healthy"
            } else {
                state = "untested"
            }
            return NodeStatus(node: NodeCatalog.nodeKey(of: url), state: state, bps: route?.bps ?? 0)
        }
    }
}
