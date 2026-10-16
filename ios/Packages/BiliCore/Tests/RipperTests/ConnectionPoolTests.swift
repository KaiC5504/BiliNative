import XCTest
import BiliShared
@testable import Ripper

final class ConnectionPoolTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition never became true")
    }

    func testWaitsForRelease() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 1 }
        XCTAssertEqual(pool.active, 1)
        held.release()
        held.release()
        let second = try await waiter.value
        XCTAssertEqual(pool.active, 1)
        second.release()
        XCTAssertEqual(pool.active, 0)
    }

    func testClassThenPriorityThenArrival() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let order = Locked<[String]>([])
        var tasks: [Task<Void, Error>] = []
        for (name, priority, queueClass) in [("low", 0.0, QueueClass.ordinary), ("high", 50.0, .ordinary), ("critical", 0.0, .critical)] {
            let expected = tasks.count + 1
            tasks.append(Task {
                let permit = try await pool.acquire(priority: priority, queueClass: queueClass)
                order.withLock { $0.append(name) }
                permit.release()
            })
            try await waitUntil { pool.queued == expected }
        }
        held.release()
        for task in tasks { try await task.value }
        XCTAssertEqual(order.current, ["critical", "high", "low"])
    }

    func testOverdueDeadlineWinsWithinAClass() async throws {
        let manual = ManualClock(10_000)
        let pool = ConnectionPool(limit: 1, clock: manual.clock)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let order = Locked<[String]>([])
        let relaxed = Task {
            let permit = try await pool.acquire(priority: 5, queueClass: .ordinary)
            order.withLock { $0.append("relaxed") }
            permit.release()
        }
        try await waitUntil { pool.queued == 1 }
        let urgent = Task {
            let permit = try await pool.acquire(priority: 0, queueClass: .ordinary, deadline: { 9_000 })
            order.withLock { $0.append("urgent") }
            permit.release()
        }
        try await waitUntil { pool.queued == 2 }
        held.release()
        try await relaxed.value
        try await urgent.value
        XCTAssertEqual(order.current, ["urgent", "relaxed"])
    }

    func testCancellingAWaiterRemovesIt() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 1 }
        waiter.cancel()
        do {
            _ = try await waiter.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(pool.queued, 0)
        held.release()
        XCTAssertEqual(pool.active, 0)
    }

    func testRaisingTheLimitGrantsWaiters() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 1 }
        pool.setLimit(2)
        let second = try await waiter.value
        XCTAssertEqual(pool.active, 2)
        held.release()
        second.release()
    }

    func testCancelledWaiterIsNeverGrantedAPermit() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let cancelled = Task { try await pool.acquire(priority: 100, queueClass: .critical) }
        try await waitUntil { pool.queued == 1 }
        let survivor = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 2 }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(pool.queued, 1)
        held.release()
        let permit = try await survivor.value
        XCTAssertEqual(pool.active, 1)
        XCTAssertEqual(pool.queued, 0)
        permit.release()
        XCTAssertEqual(pool.active, 0)
    }

    func testAcquireInAnAlreadyCancelledTaskThrowsWithoutQueueing() async throws {
        let pool = ConnectionPool(limit: 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pool.acquire(priority: 0, queueClass: .ordinary)
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(pool.active, 0)
        XCTAssertEqual(pool.queued, 0)
        let permit = try await pool.acquire(priority: 0, queueClass: .ordinary)
        XCTAssertEqual(pool.active, 1)
        permit.release()
    }

    func testReleasingTwiceDoesNotRaiseCapacity() async throws {
        let pool = ConnectionPool(limit: 1)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        held.release()
        held.release()
        XCTAssertEqual(pool.active, 0)
        let first = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 1 }
        held.release()
        XCTAssertEqual(pool.active, 1)
        XCTAssertEqual(pool.queued, 1)
        first.release()
        let second = try await waiter.value
        XCTAssertEqual(pool.active, 1)
        second.release()
        XCTAssertEqual(pool.active, 0)
    }

    func testLoweringTheLimitDoesNotStrandWaiters() async throws {
        let pool = ConnectionPool(limit: 2)
        let first = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let second = try await pool.acquire(priority: 0, queueClass: .ordinary)
        pool.setLimit(1)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { pool.queued == 1 }
        first.release()
        XCTAssertEqual(pool.active, 1)
        XCTAssertEqual(pool.queued, 1)
        second.release()
        let third = try await waiter.value
        XCTAssertEqual(pool.active, 1)
        XCTAssertEqual(pool.limit, 1)
        third.release()
        XCTAssertEqual(pool.active, 0)
    }

    func testLimitIsClamped() {
        XCTAssertEqual(ConnectionPool(limit: 0).limit, 1)
        XCTAssertEqual(ConnectionPool(limit: 10_000).limit, 512)
        let pool = ConnectionPool(limit: 4)
        pool.setLimit(-3)
        XCTAssertEqual(pool.limit, 1)
    }

    func testClassBeatsAnOverdueDeadline() async throws {
        let manual = ManualClock(10_000)
        let pool = ConnectionPool(limit: 1, clock: manual.clock)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let order = Locked<[String]>([])
        let overdue = Task {
            let permit = try await pool.acquire(priority: 50, queueClass: .ordinary, deadline: { 0 })
            order.withLock { $0.append("overdue") }
            permit.release()
        }
        try await waitUntil { pool.queued == 1 }
        let startup = Task {
            let permit = try await pool.acquire(priority: 0, queueClass: .startup)
            order.withLock { $0.append("startup") }
            permit.release()
        }
        try await waitUntil { pool.queued == 2 }
        held.release()
        try await overdue.value
        try await startup.value
        XCTAssertEqual(order.current, ["startup", "overdue"])
    }

    func testLongWaitingRequestWithADeadlineOvertakesNewerOnes() async throws {
        let manual = ManualClock(0)
        let pool = ConnectionPool(limit: 1, clock: manual.clock)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let order = Locked<[String]>([])
        let old = Task {
            let permit = try await pool.acquire(priority: 0, queueClass: .ordinary, deadline: { 1_000_000 })
            order.withLock { $0.append("old") }
            permit.release()
        }
        try await waitUntil { pool.queued == 1 }
        manual.advance(900)
        let newer = Task {
            let permit = try await pool.acquire(priority: 10, queueClass: .ordinary)
            order.withLock { $0.append("newer") }
            permit.release()
        }
        try await waitUntil { pool.queued == 2 }
        held.release()
        try await old.value
        try await newer.value
        XCTAssertEqual(order.current, ["old", "newer"])
    }

    func testInfiniteDeadlineDoesNotAge() async throws {
        let manual = ManualClock(0)
        let pool = ConnectionPool(limit: 1, clock: manual.clock)
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let order = Locked<[String]>([])
        let unbounded = Task {
            let permit = try await pool.acquire(priority: 0, queueClass: .ordinary, deadline: { .infinity })
            order.withLock { $0.append("unbounded") }
            permit.release()
        }
        try await waitUntil { pool.queued == 1 }
        manual.advance(4_500)
        let newer = Task {
            let permit = try await pool.acquire(priority: 10, queueClass: .ordinary)
            order.withLock { $0.append("newer") }
            permit.release()
        }
        try await waitUntil { pool.queued == 2 }
        held.release()
        try await unbounded.value
        try await newer.value
        XCTAssertEqual(order.current, ["newer", "unbounded"])
    }

    func testCancellationRacingAFreePoolNeverLeaksAPermit() async throws {
        let pool = ConnectionPool(limit: 1)
        for _ in 0..<300 {
            let task = Task { try await pool.acquire(priority: 0, queueClass: .critical) }
            task.cancel()
            if let permit = try? await task.value { permit.release() }
            XCTAssertEqual(pool.active, 0)
            XCTAssertEqual(pool.queued, 0)
        }
    }

    func testOnChangeReportsEveryStateChange() async throws {
        let pool = ConnectionPool(limit: 1)
        let events = Locked<[[Int]]>([])
        pool.onChange = { active, limit, queued in events.withLock { $0.append([active, limit, queued]) } }
        let held = try await pool.acquire(priority: 0, queueClass: .ordinary)
        let waiter = Task { try await pool.acquire(priority: 0, queueClass: .ordinary) }
        try await waitUntil { events.current.contains([1, 1, 1]) }
        held.release()
        let second = try await waiter.value
        second.release()
        let seen = events.current
        XCTAssertTrue(seen.contains([1, 1, 0]))
        XCTAssertTrue(seen.contains([1, 1, 1]))
        XCTAssertEqual(seen.last, [0, 1, 0])
    }

    func testOnChangeMayReadThePool() async throws {
        let pool = ConnectionPool(limit: 1)
        let seen = Locked<[Int]>([])
        pool.onChange = { _, _, _ in seen.withLock { $0.append(pool.active) } }
        let permit = try await pool.acquire(priority: 0, queueClass: .ordinary)
        permit.release()
        XCTAssertFalse(seen.current.isEmpty)
    }

    func testStressNeverExceedsTheLimitAndLeaksNothing() async throws {
        let pool = ConnectionPool(limit: 3)
        let inFlight = Locked(0)
        let peak = Locked(0)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<150 {
                group.addTask {
                    let inner = Task {
                        let permit = try await pool.acquire(priority: Double(index % 7), queueClass: index % 5 == 0 ? .critical : .ordinary)
                        let now = inFlight.withLock { value -> Int in
                            value += 1
                            return value
                        }
                        peak.withLock { $0 = max($0, now) }
                        await Task.yield()
                        inFlight.withLock { $0 -= 1 }
                        permit.release()
                    }
                    if index % 3 == 0 {
                        await Task.yield()
                        inner.cancel()
                    }
                    _ = try? await inner.value
                }
            }
        }
        XCTAssertLessThanOrEqual(peak.current, 3)
        XCTAssertEqual(pool.active, 0)
        XCTAssertEqual(pool.queued, 0)
        let permit = try await pool.acquire(priority: 0, queueClass: .ordinary)
        XCTAssertEqual(pool.active, 1)
        permit.release()
    }
}
