import BiliShared

/// What the downloads have measured about each node: how long its first byte takes, how fast one
/// connection runs and how many it carries at once (BTR PR 11 `createNodeStats`). One record is shared
/// by every track, so the audio track and the range after a seek start from what is already known.
final class NodeStats: @unchecked Sendable {
    private struct Node {
        var inflight = 0
        var receiving = 0
        var ttfbMs = 0.0
        var bps = 0.0
        var load = 0.0
        var limit = Int.max
    }

    private let nodes = Locked<[String: Node]>([:])

    private func update(_ url: String, _ change: (inout Node) -> Void) {
        let key = NodeCatalog.nodeKey(of: url)
        nodes.withLock { change(&$0[key, default: Node()]) }
    }

    private func read<Value>(_ url: String, _ get: (Node) -> Value) -> Value {
        let key = NodeCatalog.nodeKey(of: url)
        return nodes.withLock { get($0[key] ?? Node()) }
    }

    func begin(_ url: String) {
        update(url) { $0.inflight += 1 }
    }

    func firstByte(_ url: String, ms: Double) {
        update(url) { node in
            node.receiving += 1
            node.ttfbMs = smoothed(node.ttfbMs, max(1, ms))
        }
    }

    func end(_ url: String, receiving: Bool) {
        update(url) { node in
            node.inflight = max(0, node.inflight - 1)
            if receiving { node.receiving = max(0, node.receiving - 1) }
        }
    }

    func body(_ url: String, bytes: Int64, ms: Double) {
        // An index of a few KiB arrives in one packet and says nothing about speed.
        guard bytes >= 32 * 1024 else { return }
        update(url) { node in
            node.bps = smoothed(node.bps, Double(bytes) / max(0.02, ms / 1000))
            node.load = smoothed(node.load, Double(node.inflight))
        }
    }

    /// No first byte in time. While the node was sending other pieces the request was only queued behind
    /// them (HTTP/1.1 allows a few connections per host), so the node is capped at what it was carrying;
    /// otherwise the node itself is slow to answer (BTR PR 11).
    func silent(_ url: String, waitedMs: Double) {
        update(url) { node in
            if node.receiving > 0 {
                node.limit = min(node.limit, node.receiving)
            } else {
                node.ttfbMs = smoothed(node.ttfbMs, waitedMs)
            }
        }
    }

    /// The other copy of the piece won before this node had sent anything; how long this copy had
    /// waited is the least its first byte would have taken.
    func outrun(_ url: String, waitedMs: Double) {
        update(url) { node in
            if waitedMs > node.ttfbMs { node.ttfbMs = smoothed(node.ttfbMs, waitedMs) }
        }
    }

    /// The other copy won while this node was still sending. An outrun transfer never reaches `body`, so a
    /// node that answers at once and then trickles would keep the speed it showed on a part of the file
    /// it had ready, and keep getting most of the pieces.
    func crawl(_ url: String, bytes: Int64, ms: Double) {
        update(url) { node in
            let bps = Double(bytes) / max(0.02, ms / 1000)
            if ms >= 300 && bps < node.bps { node.bps = smoothed(node.bps, bps) }
        }
    }

    /// A node that is sending other pieces is alive, whatever happened to this one.
    func isBusy(_ url: String) -> Bool { read(url) { $0.receiving > 0 } }

    func isFull(_ url: String, extraInflight: Int = 0) -> Bool { read(url) { $0.inflight + extraInflight >= $0.limit } }

    func isKnown(_ url: String) -> Bool { read(url) { $0.bps > 0 } }

    func inflight(_ url: String) -> Int { read(url) { $0.inflight } }

    func ttfbMs(_ url: String) -> Double { read(url) { $0.ttfbMs } }

    func bps(_ url: String) -> Double { read(url) { $0.bps } }

    /// First byte plus the transfer at the speed one connection would get if `extraInflight` more pieces
    /// joined the ones already running. The speed was measured while the node carried `load` connections;
    /// beyond that it is assumed to share the same total, and a node that keeps its speed raises `load`
    /// with the next measurements. A node is taken to carry at least four at full speed, which is the
    /// reason to split a download at all. Nil until a speed is known.
    func expectedMs(_ url: String, pieceBytes: Int64, extraInflight: Int = 0) -> Double? {
        read(url) { node -> Double? in
            guard node.bps > 0 else { return nil }
            let width = max(4.0, node.load)
            let perConnection = node.bps * width / max(width, Double(node.inflight + extraInflight + 1))
            return node.ttfbMs + Double(pieceBytes) / perConnection * 1000
        }
    }

    /// The network path changed: what was measured on the old one is dropped. Transfers still running
    /// stay counted, so their `end` balances.
    func reset() {
        nodes.withLock { all in
            all = all.mapValues { Node(inflight: $0.inflight, receiving: $0.receiving) }
        }
    }
}
