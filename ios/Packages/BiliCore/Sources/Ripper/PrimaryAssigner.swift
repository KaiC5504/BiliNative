import BiliShared

/// BTR `assignPrimaries`: which node each piece tries first. Faster nodes get more pieces in
/// smooth weighted turns; a node under a twelfth of the fastest gets none; unmeasured nodes get a
/// trial piece or two from the end of the range.
final class PrimaryAssigner: @unchecked Sendable {
    private struct TrialState { var waited = 0; var cursor = 0 }
    private let state = Locked((turn: 0, trials: [ObjectIdentifier: TrialState]()))

    func assign(urls input: [String], count input2: Int, speed: (String) -> Double, trialKey: ObjectIdentifier) -> [String] {
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
            return (0..<count).map { urls[($0 + turn) % urls.count] }
        }
        let eligible = urls.indices.filter { known[$0] == 0 || known[$0] >= top / 12 }.map { urls[$0] }
        if !eligible.isEmpty && eligible.count < urls.count {
            urls = eligible
            known = urls.map(speed)
        }
        let unknown = urls.indices.filter { known[$0] == 0 }.map { urls[$0] }
        var trials = min(unknown.count * 2, count / 4)
        var trialState = state.withLock { $0.trials[trialKey] } ?? TrialState()
        // Small ranges never have a piece to spare; every fourth one gives up its last piece for a trial.
        if trials == 0 && !unknown.isEmpty && count >= 2 {
            trialState.waited += 1
            if trialState.waited >= 4 { trials = 1 }
        }
        if trials > 0 { trialState.waited = 0 }
        if !unknown.isEmpty {
            urls = urls.indices.filter { known[$0] > 0 }.map { urls[$0] }
            known = urls.map(speed)
            count -= trials
        }
        let weights = known.map { max($0, top * 0.05) }
        let total = weights.reduce(0, +)
        var credit = [Double](repeating: 0, count: urls.count)
        let order = urls.indices.map { ($0 + turn) % urls.count }
        var primaries: [String] = []
        for _ in 0..<max(0, count) {
            var best = order[0]
            for index in order {
                credit[index] += weights[index]
                if credit[index] > credit[best] { best = index }
            }
            credit[best] -= total
            primaries.append(urls[best])
        }
        for index in 0..<trials {
            primaries.append(unknown[(index + trialState.cursor) % unknown.count])
        }
        trialState.cursor = (trialState.cursor + trials) % 4096
        let finalState = trialState
        state.withLock { $0.trials[trialKey] = finalState }
        return primaries
    }
}
