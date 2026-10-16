# Hurry Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cold starts and the first seconds after a seek fast on 4K, so that one silent node can no longer hold
a segment for 5.5 s.

**Architecture:** When the segment being fetched starts less than 10 s ahead of the playhead, the engine is "in a
hurry" and changes three things:
- Pieces are spread over nodes by expected finish time, and no node gets more than half.
- Pieces are small.
- A late piece gets a second copy after 250-600 ms, and a third copy when the second is late too.

A per-node record of first-byte time, speed and load (`NodeStats`, from BTR PR 11) feeds those decisions. It also
stops striking a node whose request only queued behind its own other transfers. Separately, a prefetch the player
adopted is no longer thrown away when the player cancels its request.

**Tech Stack:** Swift 5 mode, Foundation only (`ios/Packages/BiliCore`), XCTest, `swift test` on Windows and macOS.
One small app change (Task 7) is tested in CI.

**Spec:** `docs/superpowers/specs/2026-10-16-m1-playback-core-design.md` section 8 ("Hurry mode (deferred)"), the
evidence in `docs/m1-results.md`, and the rules in `docs/background.md` ("Hurry mode"). The reference JS is
KaiC's BTR PR 11: `git -C D:\Repos\Apps\Bilibili-thread-ripper show a7e5f38 -- src/cdn-resolver.js
src/idm-downloader.js`. Read it for the rules, then port them into this engine's structure. Do not copy its
structure.

## Evidence this plan answers (from `logs/2026-10-16/95717dac5c86450f.jsonl`)

- **Cold 4K start, 8.7 s (BV1jt421t7XH, 19 Mbps).**
  - Segment 2 (8 MB) was a prefetch, cut into 1 MB pieces.
  - Seven pieces arrived within 1 s. One piece trickled on Akamai (478 KB in 5 s), and its backup copy on cosov
    trickled too (476 KB in 3.9 s). With only two copies allowed, nothing else was tried.
  - AVPlayer adopted that prefetch, got no bytes for 5 s, and cancelled its request. The cancel also cancelled the
    prefetch, so all 7 finished pieces were thrown away and downloaded again.
- **One cold jump banned both fastest nodes for the rest of the video (BV1bmpt6WEom at 1:49:47).** Akamai and
  cosov each got two first-byte timeouts at the same moment, while both were busy sending other pieces.
- **Post-seek stalls on 4K.** Cold ranges answered with a 1.2-2.5 s first byte on every node, and 1 MB pieces
  waited the full delay before a backup started.

## Global Constraints

- `ios/Packages/BiliCore` is Foundation-only, has no third-party packages, uses Swift 5 language mode, and must
  build and pass `swift test` on Windows as well as macOS.
- The BTR port keeps BTR's MIT notice (`ios/Packages/BiliCore/Sources/Ripper/LICENSE-BTR.txt`). Ported rules
  get a one-line `BTR PR 11` reference in a comment where the rule is non-obvious.
- Hurry threshold: a segment whose start is less than `hurryAheadSeconds = 10` seconds of playback ahead of the
  playhead (spec section 8). Startup and seek ranges are always in a hurry.
- Hurry hedge budgets (PR 11):
  - No first byte yet: the second copy starts after `clamp(ttfb × 2, 250, 600)` ms, or after 250 ms when the
    node's ttfb is unknown.
  - Bytes stopped arriving: a copy starts after a 1000 ms gap.
  - Slow transfer: a copy starts at `elapsed ≥ max(400, expected × 2)` while under 75% of the piece has arrived.
  - At most three copies of a piece.
- Hurry placement cost (PR 11 `pick`):
  - Unknown node: `best × 2 × (inflight + 1)`, or `inflight` when no node is known.
  - `+1e5` for a node already carrying at least 2 pieces and more than half of all in flight, when there are 3 or
    more hosts.
  - `+1` for an address that has not delivered.
  - `+1e6` for a full node.
- Node stats blend new samples 0.7 old / 0.3 new (the existing `smoothed`). Body samples under 32 KiB are ignored.
  A crawl counts only at 300 ms or more and only when slower than the current speed. A node is assumed to carry at
  least 4 connections at full speed.
- Nothing in the engine logs cookies, signed query strings or tokens. Engine logs keep using
  `NodeCatalog.nodeKey`.
- `RipperConfig.hurry` (default `true`) switches all of it off, for the bench comparison and as a kill switch.

## Review Focus

1. **Akamai-only account (one host).** Hurry placement must give every piece to the single node, without the
   half-share penalty. Test in Task 3.
2. **A busy node whose new requests never get a first byte.** Exempting busy nodes from strikes must not loop
   forever: the range still completes from other nodes, and the node's `limit` stops new pieces piling onto it.
   Test in Task 2.
3. **No node known yet (first range of a session).** Placement falls back to spreading by in-flight count, and the
   probe head still runs. Test in Task 3.
4. **Duplicate traffic.** Third copies happen only in a hurry, and only after the second copy is late. A range
   outside hurry never starts a third copy. Test in Task 4.
5. **The player cancels an adopted prefetch, then the session closes.** The prefetch survives the cancel, but
   `close()` and `dropPrefetch` (seek) still cancel it. Test in Task 5.

---

### Task 1: NodeStats

**Files:**
- Create: `ios/Packages/BiliCore/Sources/Ripper/NodeStats.swift`
- Modify: `ios/Packages/BiliCore/Sources/Ripper/Attempt.swift`: add `var nodes = NodeStats()` to `EngineContext`
  (a defaulted stored property, so existing initialisers keep compiling), and feed it from `AttemptRunner.run`.
- Modify: `ios/Packages/BiliCore/Sources/Ripper/RipperSession.swift`: `networkChanged` also calls `ctx.nodes.reset()`.
- Test: `ios/Packages/BiliCore/Tests/RipperTests/NodeStatsTests.swift`

**Interfaces:**
- Produces (keyed by `NodeCatalog.nodeKey(of: url)`, all thread-safe through `Locked`):
  - `final class NodeStats: @unchecked Sendable`
  - `func begin(_ url: String)`
  - `func firstByte(_ url: String, ms: Double)`
  - `func end(_ url: String, receiving: Bool)`
  - `func body(_ url: String, bytes: Int64, ms: Double)`
  - `func silent(_ url: String, waitedMs: Double)`
  - `func outrun(_ url: String, waitedMs: Double)`
  - `func crawl(_ url: String, bytes: Int64, ms: Double)`
  - `func isBusy(_ url: String) -> Bool` (receiving > 0)
  - `func isFull(_ url: String) -> Bool` (inflight >= limit)
  - `func isKnown(_ url: String) -> Bool` (bps > 0)
  - `func inflight(_ url: String) -> Int`
  - `func ttfbMs(_ url: String) -> Double`
  - `func bps(_ url: String) -> Double`
  - `func expectedMs(_ url: String, pieceBytes: Int64, extraInflight: Int = 0) -> Double?`
  - `func reset()`

- [ ] **Step 1: Write the failing tests**

```swift
func testExpectedTimeSharesTheNodeBeyondItsMeasuredLoad() {
    let stats = NodeStats()
    let url = "https://upos-sz-mirrorcosov.bilivideo.com/v.m4s"
    XCTAssertNil(stats.expectedMs(url, pieceBytes: 1_000_000))
    stats.begin(url); stats.firstByte(url, ms: 100); stats.body(url, bytes: 1_000_000, ms: 500); stats.end(url, receiving: true)
    // 2 MB/s on one connection, ttfb 100 ms, load blended from 1 in flight; width = max(4, load) = 4.
    XCTAssertEqual(stats.expectedMs(url, pieceBytes: 1_000_000)!, 600, accuracy: 0.5)
    // Six more in flight: 2 MB/s × 4 / 7 per connection.
    XCTAssertEqual(stats.expectedMs(url, pieceBytes: 1_000_000, extraInflight: 6)!, 100 + 1_000_000 / (2_000_000 * 4.0 / 7) * 1000, accuracy: 0.5)
}

func testSmallBodiesSayNothingAboutSpeed() {
    let stats = NodeStats(); let url = "https://a.example/v"
    stats.body(url, bytes: 16 * 1024, ms: 10)
    XCTAssertFalse(stats.isKnown(url))
}

func testSilenceWhileReceivingCapsTheNodeOtherwiseRaisesItsFirstByteTime() {
    let stats = NodeStats(); let busy = "https://akam.example/v"; let idle = "https://cosov.example/v"
    stats.begin(busy); stats.firstByte(busy, ms: 50)           // one transfer receiving
    stats.begin(busy); stats.begin(busy)                        // two more waiting
    stats.silent(busy, waitedMs: 5_500)
    XCTAssertTrue(stats.isBusy(busy))
    XCTAssertTrue(stats.isFull(busy), "limit = what it was receiving (1), and 3 are in flight")
    XCTAssertEqual(stats.ttfbMs(busy), 50, accuracy: 0.01, "a queued request is not the node's first-byte time")
    stats.silent(idle, waitedMs: 2_000)
    XCTAssertEqual(stats.ttfbMs(idle), 2_000, accuracy: 0.01)
}

func testOutrunAndCrawlOnlyEverLowerTheEstimate() {
    let stats = NodeStats(); let url = "https://aliov.example/v"
    stats.begin(url); stats.firstByte(url, ms: 40); stats.body(url, bytes: 4_000_000, ms: 1_000); stats.end(url, receiving: true)
    stats.outrun(url, waitedMs: 30)        // shorter than the known ttfb: ignored
    XCTAssertEqual(stats.ttfbMs(url), 40, accuracy: 0.01)
    stats.outrun(url, waitedMs: 1_040)     // blended up
    XCTAssertEqual(stats.ttfbMs(url), 40 * 0.7 + 1_040 * 0.3, accuracy: 0.01)
    stats.crawl(url, bytes: 50_000, ms: 200)   // under 300 ms: ignored
    XCTAssertEqual(stats.bps(url), 4_000_000, accuracy: 1)
    stats.crawl(url, bytes: 100_000, ms: 1_000) // 100 KB/s trickle
    XCTAssertEqual(stats.bps(url), 4_000_000 * 0.7 + 100_000 * 0.3, accuracy: 1)
}

func testRunnerFeedsTheStats() async throws  // a SimCDN piece through AttemptRunner: afterwards isKnown, inflight 0, not busy; a firstByteTimeout leaves ttfb raised
func testNetworkChangeForgetsNodeStats() async throws  // RipperSession.networkChanged → ctx.nodes no longer isKnown
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter NodeStatsTests`
Expected: FAIL, `NodeStats` is not defined.

- [ ] **Step 3: Implement `NodeStats` and wire it into `AttemptRunner.run`**

The per-node record is `inflight`, `receiving`, `ttfbMs`, `bps`, `load`, and `limit` (initially `Int.max`):
- `begin` happens after the permit.
- `firstByte` happens at headers.
- `end(receiving: gotHeaders)` happens on every exit, in a `defer`.
- `body(bytes: part.length, ms: since headers)` happens on success.

On failure or cancellation, with no headers received:
- A `firstByteTimeout` calls `silent(waitedMs: elapsed)`.
- A cancelled copy calls `outrun(waitedMs: elapsed)`.

A cancelled copy with headers calls `crawl(bytes: received, ms: since headers)`. `body` also blends
`load` toward the in-flight count at that moment.

`expectedMs` follows the PR 11 algorithm, which the test pins:

```swift
let width = max(4.0, load)
let perConnection = bps * width / max(width, Double(inflight + extraInflight + 1))
return ttfbMs + Double(pieceBytes) / perConnection * 1000
```

- [ ] **Step 4: Run the tests and the whole package**

Run: `swift test --package-path ios/Packages/BiliCore`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore/Sources/Ripper/NodeStats.swift ios/Packages/BiliCore/Sources/Ripper/Attempt.swift ios/Packages/BiliCore/Sources/Ripper/RipperSession.swift ios/Packages/BiliCore/Tests/RipperTests/NodeStatsTests.swift
git commit -m "Engine: per-node first byte, speed and load (BTR PR 11 node stats)"
```

---

### Task 2: A busy node's silent request is not a strike

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/Ripper/Attempt.swift` (`AttemptRunner.run` failure branch)
- Modify: `ios/Packages/BiliCore/Tests/RipperTests/SimCDN.swift`: add `Behavior.lateFirstByteFromRequest: Int?`.
  Requests numbered at or above it on that node take `coldFirstByteMs` to the first byte.
- Test: `ios/Packages/BiliCore/Tests/RipperTests/RangeDownloaderTests.swift`

**Interfaces:**
- Consumes: `NodeStats.isBusy` (Task 1).
- Produces: the log field `"busy": true` on `attempt failed` events.

- [ ] **Step 1: Write the failing tests**

```swift
func testSilentRequestsToABusyNodeDoNotBanIt() async throws {
    // cosov streams its first piece slowly (receiving for ~1.5 s), and every later request to it gets no first
    // byte within the timeout. The other nodes are fast.
    // After a 4 MiB range: bytes exact, resolver.bans.allowsNode(cosov url) == true, and the log has no "ban" for cosov.
}

func testABusyNodeThatNeverAnswersNewRequestsStillLetsTheRangeFinish() async throws {
    // As above but for 8 MiB with fixedConcurrency 8: the range completes within 3 s, and cosov's NodeStats isFull.
}
```

- [ ] **Step 2: Run and see them fail.** `swift test --package-path ios/Packages/BiliCore --filter RangeDownloaderTests`.
  The first test fails because cosov is banned.

- [ ] **Step 3: Implement.** The check is `received == 0`, the error is `RipperError.firstByteTimeout`, and
  `ctx.nodes.isBusy(url)` is true. Check it before this attempt's `end`; this attempt never had headers, so it is
  not counted in `receiving`. When it holds:
  - skip `resolver.failure` and `ctx.auto?.slow()`;
  - still call `ctx.stats.failed`;
  - log `attempt failed` with `"busy": true`.

  The reason (comment it, citing BTR PR 11): such a request waited behind the node's other transfers, in
  URLSession's 8-per-host limit for HTTP/1.1 Akamai, or in the node's own queue.

- [ ] **Step 4: Run the package tests.** All pass.

- [ ] **Step 5: Commit** `Engine: a silent request to a node that is sending other pieces is not held against it`

---

### Task 3: Hurry flag, small pieces and placement by expected finish

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/Ripper/RipperConfig.swift`: add `public var hurry = true` and
  `public var hurryAheadSeconds = 10.0`.
- Create: `ios/Packages/BiliCore/Sources/Ripper/HurryPlacement.swift`
- Modify: `ios/Packages/BiliCore/Sources/Ripper/RangeDownloader.swift`: `stream` and `run` take
  `hurry: (@Sendable () -> Bool)? = nil`.
- Modify: `ios/Packages/BiliCore/Sources/Ripper/RipperSession.swift`: build the hurry closure for player reads
  and prefetches.
- Test: `ios/Packages/BiliCore/Tests/RipperTests/HurryPlacementTests.swift`, plus additions to
  `RangeDownloaderTests.swift` and `RipperSessionTests.swift`.

**Interfaces:**
- Consumes: `NodeStats.expectedMs/inflight/isFull/isKnown` (Task 1); `BanList.hasDelivered(_:)`.
- Produces:
  - `enum HurryPlacement { static func assign(urls: [String], count: Int, pieceBytes: Int64, nodes: NodeStats, delivered: (String) -> Bool) -> [String] }`.
    It returns one primary per piece.
  - `RangeDownloader.stream(_:resolver:startup:priority:deadline:expectedTotal:hurry:)`.
  - `RipperSession`'s hurry closure: `config.hurry && (startup || segment.startTime - playhead < config.hurryAheadSeconds × rate)`.
    It is re-read each time it is called.

- [ ] **Step 1: Write the failing tests**

```swift
func testNoNodeKnownSpreadsByInflight()          // 3 unknown urls, 6 pieces → each url twice
func testUnknownNodesTakeAShareAtTwiceTheBestCost() // 1 known fast url + 2 unknown, 8 pieces → every url gets ≥ 1 and the known gets the most
func testNoNodeTakesMoreThanHalfWithThreeHosts()  // 1 very fast known + 2 equally slow known, nothing in flight, 10 pieces → exactly 5 fast, 3 and 2 on the slow ones (the +1e5 rule; work it through in the test comment)
func testASingleHostTakesEveryPiece()             // Akamai-only: 1 url, 5 pieces → 5 × that url (Review Focus 1)
func testFullNodesAndUndeliveredAddressesGoLast() // isFull url never chosen while another is open; equal cost → delivered address first
```

Placement keeps a virtual in-flight count per host, incremented per assigned piece and passed as `extraInflight`,
so a fast node's cost rises as it fills.

RangeDownloader:

```swift
func testHurryUsesSmallPieces() async throws
// Warm the meter with one 4 MiB non-hurry range so adaptiveMinChunk would pick 1 MiB. Then a hurry 2 MiB range
// through a RecordingTransport: every piece ≤ 256 KiB (2 MiB split over 8 connections, floor 64 KiB).

func testWarmNodesSkipTheProbeHead() async throws
// After one startup range, a second startup range starts with no 64 KiB race across all nodes: the RecordingTransport
// shows the first requests of range 2 are ordinary pieces, not one 64 KiB piece raced on every node.
```

RipperSession:

```swift
func testSegmentsNearThePlayheadAreInAHurry() async throws
// With the playhead at 0: segment 0 (0-4 s) and segment 2 (8-12 s) hurry; segment 3 (12-16 s) does not.
// With config.hurry = false, none do. Expose a test-only `hurries(_ track:, _ range:) -> Bool` in the
// "For tests." extension.
```

- [ ] **Step 2: Run and see them fail.**

- [ ] **Step 3: Implement.** In `RangeDownloader.run`, read `hurry?() ?? false` once, when the range is split:
  - In a hurry, `minChunk = ctx.config.minChunkBytes`, with no adaptive growth.
  - In a hurry, primaries come from `HurryPlacement.assign`; otherwise from `PrimaryAssigner`, unchanged.
  - The probe head runs only when `startup` and no candidate `isKnown`.

  Pass the same closure on to `PieceDownloader.download` (Task 4 uses it). `RipperSession` builds the closure next
  to `deadline(for:)` and passes it for both player reads and `schedulePrefetch`. That way a prefetch the playhead
  approaches turns into a hurry.

- [ ] **Step 4: Run the package tests.** All pass.

- [ ] **Step 5: Commit** `Engine: hurry mode spreads pieces by expected finish and keeps them small (BTR PR 11)`

---

### Task 4: Faster second copies and a third copy in a hurry

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/Ripper/PieceDownloader.swift`. `download` and `race` take
  `hurry: (@Sendable () -> Bool)?`. The race runs up to 3 copies, and copy k waits on copy k−1. Add
  `func hurryHedgeDue(previous: AttemptProgress, url: String, pieceLength: Int64) -> Bool`.
- Modify: `ios/Packages/BiliCore/Tests/RipperTests/SimCDN.swift`. Add `Behavior.coldRange: ClosedRange<Int64>?`,
  `coldRangeFirstByteMs: Double`, and `coldRangeBytesPerSecond: Double?`. A request starting inside the range gets
  that first-byte time and that rate, like a cold edge.
- Test: `ios/Packages/BiliCore/Tests/RipperTests/RangeDownloaderTests.swift`

**Interfaces:**
- Consumes: `NodeStats.ttfbMs/expectedMs` (Task 1); the hurry closure (Task 3).
- Produces: the log field `"copy": k` (1-based) on `piece` events for copies after the first.

- [ ] **Step 1: Write the failing tests**

```swift
func testHurryHedgeBudgets() {
    // A unit test on hurryHedgeDue with a hand-built AttemptProgress and the system clock offsets, as testHedgeDueRules does:
    // - no first byte, unknown ttfb: false at 200 ms, true at 260 ms
    // - no first byte, ttfb 400 ms: false at 700 ms, true at 810 ms (budget 600); ttfb 100 ms: true at 260 ms (budget 250)
    // - bytes stopped: true once the last byte is 1000 ms old
    // - slow: expected 300 ms, 50% received at 550 ms → false; at 610 ms with < 75% → true; with 80% received → false
}

func testColdRangeOnTheTwoFastestNodesIsFetchedFromAThirdInAHurry() async throws {
    // cosov and akam known fast (warmed by one range). Then a hurry range inside coldRange on both: first byte 1500 ms
    // and 100 KB/s. aliov is normal. The 1 MiB hurry range completes in under 1200 ms, and the RecordingTransport
    // shows aliov requests for pieces first placed on cosov or akam.
}

func testWithoutHurryNoThirdCopyStarts() async throws {
    // The same CDN and range with hurry nil: no piece has 3 requests in the RecordingTransport (Review Focus 4).
}

func testHurryOffInConfigKeepsTheOldTiming() async throws {
    // config.hurry = false with a hurry closure that returns true: the range takes at least 1500 ms.
    // This is the bench's comparison baseline.
}
```

- [ ] **Step 2: Run and see them fail.**

- [ ] **Step 3: Implement.**
  - `race` gets `width = mode == .probe ? limit : 3` copy slots, and the candidate walk takes up to that many at a
    time.
  - Copy k ≥ 1 waits as follows:
    - **In a hurry** (`hurry?() == true` at each 50 ms check): until `hurryHedgeDue(previous: copy k−1)` holds, or
      copy k−1 has failed.
    - **Not in a hurry:** copy 1 keeps today's `waitForCopy`. Copy 2 waits until the range turns into a hurry
      (then the hurry rule applies). If copy 1 fails first, copy 2 throws without sending a request, so the round
      moves on to the next candidates as it does today.
  - A candidate whose copy never sent a request is not counted as tried, so the walk still reaches it later in
    the round.
  - Every copy marks its own `AttemptProgress` failed on error, not only copy 0.
  - `hurryHedgeDue` uses the Global Constraints budgets, with ttfb and expected time read from `ctx.nodes` for the
    previous copy's url.

- [ ] **Step 4: Run the package tests.** All pass. Then run the existing `testHedgeDueRules` and
  `testLosingCopyIsCancelledAndSampledNotPunished`; they are unchanged.

- [ ] **Step 5: Commit** `Engine: in a hurry a late piece gets a second copy within 250-600 ms and a third if that is late too`

---

### Task 5: A prefetch the player adopted survives the player's cancel

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/Ripper/RipperSession.swift` (`serve`, the `.inflight(task)` case)
- Test: `ios/Packages/BiliCore/Tests/RipperTests/RipperSessionTests.swift`

**Interfaces:** none new.

- [ ] **Step 1: Write the failing tests**

```swift
func testCancelledReaderLeavesTheAdoptedPrefetchRunning() async throws {
    // Segment 1 is prefetched from a slow CDN (about 1 s). A read of segment 1 adopts it, and that reader is
    // cancelled after 100 ms. A second read of segment 1 then gets the bytes, with "source" prefetch or memory,
    // and the SimCDN request count for segment 1's bytes did not grow after the first prefetch.
}

func testCloseAndSeekStillCancelAPrefetchAReaderLeft() async throws {
    // Same setup, then close() → the prefetch task is cancelled (the CDN body stops; prefetchesRunning == 0).
    // Repeat with a seek read to a far segment → dropPrefetch cancels it (Review Focus 5).
}
```

- [ ] **Step 2: Run and see them fail.** The first test fails because the second read downloads again.

- [ ] **Step 3: Implement.** When the reader is cancelled, do not cancel the task. Under the lock, if the session
  is not closed and `inflight[key]` is empty, put the task back into `inflight[key]`. Its existing
  `prefetchFinished` then caches the bytes. Keep the `playerPending` bookkeeping as it is.

- [ ] **Step 4: Run the package tests.** All pass.

- [ ] **Step 5: Commit** `Engine: a prefetch the player adopted keeps going when the player cancels its request`

---

### Task 6: Bench comparison of cold seeks

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/ripper-bench/Bench.swift`

**Interfaces:**
- Consumes: `RipperConfig.hurry` (Task 3).

- [ ] **Step 1: Add `--seeks N` and `--no-hurry`.**
  - `--seeks N` takes N pseudo-random offsets from a fixed seed (17), spread over the whole video file. It
    excludes the first 5% and the last 2 MiB.
  - At each offset it reads a 4 MiB range through a fresh `RipperSession` per offset, in startup mode.
  - Per offset it prints the time to the first 1 MiB and to the whole range.
  - It ends with medians.
  - `--no-hurry` sets `config.hurry = false`.
  - Output stays redacted, as today: node keys only, no signed URLs.

- [ ] **Step 2: Run it on KaiC's saved playurl, both ways.**

```bash
swift run --package-path ios/Packages/BiliCore ripper-bench --playurl local/playurl.json --quality 120 --seeks 8
swift run --package-path ios/Packages/BiliCore ripper-bench --playurl local/playurl.json --quality 120 --seeks 8 --no-hurry
```

Expected: both runs finish. Record both median lines in the commit message. If `local/playurl.json` has expired
(HTTP 403 everywhere), say so in the report and skip this step; KaiC saves a fresh one.

- [ ] **Step 3: Commit** `Bench: cold-seek comparison with and without hurry mode`

---

### Task 7: Docs, the 卡顿 window and the phone build

**Files:**
- Modify: `ios/Sources/App/Playback/SeekTimer.swift`: `StallFilter.after` changes from 0.25 to 0.75. Phone logs
  show AVKit reporting the jump 0.35-0.65 s after the wait began.
- Modify: `ios/Tests/AppTests/PlaybackPolicyTests.swift`. In `testStallsRightAroundADragAreSeekWaits`, a stall
  reported 0.6 s before its jump is now a seek wait, and 0.9 s before is a stall.
- Modify: `docs/background.md`: under "Deviations from BTR", add hurry mode (the BTR PR 11 rules as ported), the
  busy-node rule, and adopted prefetches surviving a cancel. In "Hurry mode", say it is built and where.
- Modify: `CLAUDE.md`: Status line.

- [ ] **Step 1: Make the changes and run the package tests on the PC.**
- [ ] **Step 2: Push. Wait for the iOS compile check to go green** (`gh run list --limit 1`, then
  `gh run watch <id> --exit-status`).
- [ ] **Step 3: Ship a TestFlight build** (`python scripts/testflight.py start`, then `watch`).
- [ ] **Step 4: Report to KaiC with phone steps:**
  - Reopen BV1jt421t7XH, or any 4K video not watched today. First frame should be about 2 s or less.
  - Jump into unloaded parts 5 times; 卡顿 should stay at 0 or 1.
  - Compare against `docs/m1-results.md`.
  - Then read the logs: count `copy` 3 pieces and `busy` failures, and append the numbers to
    `docs/m1-results.md` under "Hurry mode".
- [ ] **Step 5: Commit** `Hurry mode: docs and results`
