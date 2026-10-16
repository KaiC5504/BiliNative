import BiliShared

public enum QueueClass: Int, Sendable {
    /// Init/index and the first probe of a range.
    case critical = 0
    case startup = 1
    case ordinary = 2
}

/// BTR's `Semaphore`: a connection budget whose waiters are served by class, deadline urgency and age.
public final class ConnectionPool: @unchecked Sendable {
    public final class Permit: @unchecked Sendable {
        private let released = Locked(false)
        private let onRelease: @Sendable () -> Void

        init(onRelease: @escaping @Sendable () -> Void) {
            self.onRelease = onRelease
        }

        public func release() {
            let already = released.withLock { value -> Bool in
                defer { value = true }
                return value
            }
            if !already { onRelease() }
        }
    }

    private struct Waiter {
        let id: UInt64
        let priority: Double
        let queueClass: QueueClass
        let deadline: (@Sendable () -> Double)?
        let ages: Bool
        let queuedAt: Double
        let continuation: CheckedContinuation<Permit, Error>
    }

    private struct State {
        var limit: Int
        var active = 0
        var queue: [Waiter] = []
        var nextID: UInt64 = 0
    }

    /// A hedge copy's +20 is worth 0.9 s of waiting.
    static let agingPerMs = 20.0 / 900.0

    private let state: Locked<State>
    private let clock: MonotonicClock
    private let changeHandler = Locked<((_ active: Int, _ limit: Int, _ queued: Int) -> Void)?>(nil)

    /// Called after every change, outside the pool's lock, so the handler may read the pool.
    public var onChange: ((_ active: Int, _ limit: Int, _ queued: Int) -> Void)? {
        get { changeHandler.current }
        set { changeHandler.withLock { $0 = newValue } }
    }

    public init(limit: Int, clock: MonotonicClock = .system) {
        state = Locked(State(limit: max(1, min(512, limit))))
        self.clock = clock
    }

    public var limit: Int { state.current.limit }
    public var active: Int { state.current.active }
    public var queued: Int { state.current.queue.count }

    public func setLimit(_ limit: Int) {
        state.withLock { $0.limit = max(1, min(512, limit)) }
        drain()
    }

    /// `deadline` returns the monotonic time (ms) playback needs this request; it is re-read on every pass.
    public func acquire(priority: Double, queueClass: QueueClass, deadline: (@Sendable () -> Double)? = nil) async throws -> Permit {
        try Task.checkCancellation()
        let id = state.withLock { value -> UInt64 in
            value.nextID += 1
            return value.nextID
        }
        let ages = queueClass == .ordinary && (deadline.map { $0().isFinite } ?? false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Permit, Error>) in
                let queuedAt = clock.nowMs()
                state.withLock {
                    $0.queue.append(Waiter(id: id, priority: priority, queueClass: queueClass, deadline: deadline,
                                           ages: ages, queuedAt: queuedAt, continuation: continuation))
                }
                // The cancellation handler may have run before the waiter was queued; checking before the
                // drain keeps a cancelled task from being granted a permit it would only have to give back.
                if Task.isCancelled {
                    cancelWaiter(id)
                } else {
                    drain()
                }
            }
        } onCancel: { [weak self] in
            self?.cancelWaiter(id)
        }
    }

    /// Whoever removes the waiter from the queue under the lock owns its continuation, so it is resumed once.
    private func cancelWaiter(_ id: UInt64) {
        let waiter = state.withLock { value -> Waiter? in
            guard let index = value.queue.firstIndex(where: { $0.id == id }) else { return nil }
            return value.queue.remove(at: index)
        }
        guard let waiter else { return }
        waiter.continuation.resume(throwing: CancellationError())
        notify()
    }

    private func releaseOne() {
        state.withLock { $0.active = max(0, $0.active - 1) }
        drain()
    }

    private func drain() {
        let now = clock.nowMs()
        var grants: [CheckedContinuation<Permit, Error>] = []
        state.withLock { value in
            while value.active < value.limit, !value.queue.isEmpty {
                func rank(_ waiter: Waiter) -> Double {
                    var urgency = 0.0
                    if let deadline = waiter.deadline?(), deadline.isFinite {
                        let remaining = deadline - now
                        urgency = remaining <= 0 ? 12 : remaining <= 750 ? 9 : remaining <= 2_000 ? 6 : 0
                    }
                    return waiter.priority + urgency + (waiter.ages ? (now - waiter.queuedAt) * Self.agingPerMs : 0)
                }
                var best = 0
                var bestRank = rank(value.queue[0])
                for index in 1..<value.queue.count {
                    let candidate = value.queue[index]
                    let current = value.queue[best]
                    let candidateRank = rank(candidate)
                    if candidate.queueClass.rawValue < current.queueClass.rawValue
                        || (candidate.queueClass == current.queueClass && candidateRank > bestRank) {
                        best = index
                        bestRank = candidateRank
                    }
                }
                let waiter = value.queue.remove(at: best)
                value.active += 1
                grants.append(waiter.continuation)
            }
        }
        for continuation in grants {
            continuation.resume(returning: Permit { [weak self] in self?.releaseOne() })
        }
        notify()
    }

    private func notify() {
        let value = state.current
        changeHandler.current?(value.active, value.limit, value.queue.count)
    }
}
