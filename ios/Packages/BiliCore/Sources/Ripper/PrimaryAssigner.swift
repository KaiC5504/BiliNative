import BiliShared

/// BTR `assignPrimaries`: which node each piece tries first. Faster nodes get more pieces in
/// smooth weighted turns; a node under a twelfth of the fastest gets none; unmeasured nodes get a
/// trial piece or two from the end of the range. A full node (`isFull`, given the pieces placed on it
/// so far) sits its turns out while another node has room.
final class PrimaryAssigner: @unchecked Sendable {
    private struct TrialState { var waited = 0; var cursor = 0 }
    private let state = Locked((turn: 0, trials: [ObjectIdentifier: TrialState]()))

    func assign(urls input: [String], count input2: Int, speed: (String) -> Double, trialKey: ObjectIdentifier,
                isFull: (_ url: String, _ placed: Int) -> Bool = { _, _ in false }) -> [String] {
        var urls = input
        var count = input2
        guard !urls.isEmpty, count > 0 else { return [] }
        if urls.count == 1 { return Array(repeating: urls[0], count: count) }
        let turn = state.withLock { value -> Int in
            defer { value.turn = (value.turn + 1) % 4096 }
            return value.turn
        }
        var known = urls.map(speed)
        guard let top = known.max(), top > 0 else {
            return Self.turns(urls, weights: urls.map { _ in 1 }, count: count, turn: turn, isFull: isFull)
        }
        let eligible = urls.indices.filter { known[$0] == 0 || known[$0] >= top / 12 }.map { urls[$0] }
        if !eligible.isEmpty && eligible.count < urls.count {
            urls = eligible
            known = urls.map(speed)
        }
        let unknown = urls.indices.filter { known[$0] == 0 }.map { urls[$0] }
        let spare = min(unknown.count * 2, count / 4)
        let pieceCount = count
        // One lock section for the whole read-modify-write: the video and audio ranges assign concurrently.
        let (trials, trialCursor) = state.withLock { value -> (Int, Int) in
            var trialState = value.trials[trialKey] ?? TrialState()
            var trials = spare
            // Small ranges never have a piece to spare; every fourth one gives up its last piece for a trial.
            if trials == 0 && !unknown.isEmpty && pieceCount >= 2 {
                trialState.waited += 1
                if trialState.waited >= 4 { trials = 1 }
            }
            if trials > 0 { trialState.waited = 0 }
            let cursor = trialState.cursor
            trialState.cursor = (trialState.cursor + trials) % 4096
            value.trials[trialKey] = trialState
            return (trials, cursor)
        }
        if !unknown.isEmpty {
            urls = urls.indices.filter { known[$0] > 0 }.map { urls[$0] }
            known = urls.map(speed)
            count -= trials
        }
        var primaries = Self.turns(urls, weights: known.map { max($0, top * 0.05) }, count: max(0, count), turn: turn, isFull: isFull)
        for index in 0..<trials {
            primaries.append(unknown[(index + trialCursor) % unknown.count])
        }
        return primaries
    }

    /// Only the nodes taking turns earn credit, so the pieces a full node cannot take are shared out by weight.
    private static func turns(_ urls: [String], weights: [Double], count: Int, turn: Int, isFull: (String, Int) -> Bool) -> [String] {
        let keys = urls.map(NodeCatalog.nodeKey(of:))
        var credit = [Double](repeating: 0, count: urls.count)
        var placed: [String: Int] = [:]
        let order = urls.indices.map { ($0 + turn) % urls.count }
        var primaries: [String] = []
        for _ in 0..<count {
            let open = order.filter { !isFull(urls[$0], placed[keys[$0], default: 0]) }
            let taking = open.isEmpty ? order : open
            var best = taking[0]
            for index in taking {
                credit[index] += weights[index]
                if credit[index] > credit[best] { best = index }
            }
            credit[best] -= taking.reduce(0) { $0 + weights[$1] }
            placed[keys[best], default: 0] += 1
            primaries.append(urls[best])
        }
        return primaries
    }
}
