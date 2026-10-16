/// Which node each piece of a range in a hurry tries first: the one expected to deliver it first, counting
/// the pieces already placed on it (BTR PR 11 `pick`). One measurement must not decide where a whole segment
/// goes while the player is short of data: a node can take seconds over a part of the file it has not served
/// lately. So unknown nodes take a share and, with three or more hosts, no node takes more than half.
enum HurryPlacement {
    static func assign(urls: [String], count: Int, pieceBytes: Int64, nodes: NodeStats, delivered: (String) -> Bool) -> [String] {
        guard !urls.isEmpty, count > 0 else { return [] }
        let keys = urls.map(NodeCatalog.nodeKey(of:))
        let hosts = Set(keys)
        var placed: [String: Int] = [:]
        var primaries: [String] = []
        primaries.reserveCapacity(count)
        for _ in 0..<count {
            let inflight = urls.indices.map { nodes.inflight(urls[$0]) + placed[keys[$0], default: 0] }
            let expected = urls.indices.map { nodes.expectedMs(urls[$0], pieceBytes: pieceBytes, extraInflight: placed[keys[$0], default: 0]) }
            let best = expected.compactMap { $0 }.min()
            var carried = 0
            for host in hosts {
                guard let index = keys.firstIndex(of: host) else { continue }
                carried += inflight[index]
            }
            var chosen = 0
            var chosenCost = Double.infinity
            for index in urls.indices {
                let url = urls[index]
                let cost = Self.cost(expected: expected[index], best: best, inflight: inflight[index],
                                     crowded: hosts.count > 2 && inflight[index] >= 2 && inflight[index] * 2 > carried,
                                     delivered: delivered(url), full: nodes.isFull(url, extraInflight: placed[keys[index], default: 0]))
                // Equal costs go to the node carrying less, so equally slow nodes share the overflow.
                if cost < chosenCost || (cost == chosenCost && inflight[index] < inflight[chosen]) {
                    chosen = index
                    chosenCost = cost
                }
            }
            placed[keys[chosen], default: 0] += 1
            primaries.append(urls[chosen])
        }
        return primaries
    }

    /// The candidates for a later copy of a piece in a hurry, the one expected to deliver first first, at the costs
    /// `assign` gives unknown, full and not yet delivering nodes. A copy is one request, not a share of a segment, so
    /// a node carrying more than half may take it.
    static func byExpectedFinish(_ urls: [String], pieceBytes: Int64, nodes: NodeStats, delivered: (String) -> Bool) -> [String] {
        let expected = urls.map { nodes.expectedMs($0, pieceBytes: pieceBytes) }
        let best = expected.compactMap { $0 }.min()
        let costs = urls.indices.map { index in
            Self.cost(expected: expected[index], best: best, inflight: nodes.inflight(urls[index]), crowded: false,
                      delivered: delivered(urls[index]), full: nodes.isFull(urls[index]))
        }
        return urls.indices.sorted { (costs[$0], $0) < (costs[$1], $1) }.map { urls[$0] }
    }

    /// A node not measured yet costs twice the best known one, times its pieces in flight plus one.
    private static func cost(expected: Double?, best: Double?, inflight: Int, crowded: Bool, delivered: Bool, full: Bool) -> Double {
        var cost = expected ?? best.map { $0 * 2 * Double(inflight + 1) } ?? Double(inflight)
        if crowded { cost += 1e5 }
        if !delivered { cost += 1 }
        if full { cost += 1e6 }
        return cost
    }
}
