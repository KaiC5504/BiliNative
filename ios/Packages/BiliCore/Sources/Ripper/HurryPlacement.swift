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
                var cost: Double
                if let value = expected[index] {
                    cost = value
                } else if let best {
                    cost = best * 2 * Double(inflight[index] + 1)
                } else {
                    cost = Double(inflight[index])
                }
                if hosts.count > 2 && inflight[index] >= 2 && inflight[index] * 2 > carried { cost += 1e5 }
                if !delivered(url) { cost += 1 }
                if nodes.isFull(url, extraInflight: placed[keys[index], default: 0]) { cost += 1e6 }
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
}
