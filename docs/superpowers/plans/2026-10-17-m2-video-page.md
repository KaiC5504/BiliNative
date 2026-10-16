# Milestone 2: Player and Video Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the M1 test bench with the official app's player and video page (chrome, gestures, danmaku, actions, comments, related, history) on top of the BTR engine, shipped as two TestFlight builds.

**Architecture:** Logic that needs no UIKit goes into BiliCore (new targets `Danmaku` and `AppLogic`, plus new calls in `BiliAPI`) and is tested with `swift test` on the PC. The app gets a custom player over `AVPlayerLayer` (no `AVPlayerViewController`), a `VideoPageModel` that owns one `PlaybackController` per part, and SwiftUI screens copied from the official screenshots. App code is verified in CI (compile check, simulator tests, demo screenshots).

**Tech Stack:** Swift 5 mode, SwiftUI + UIKit, AVFoundation/AVKit (`AVPictureInPictureController`), MediaPlayer (`MPVolumeView`), Photos (add-only), XCTest, XcodeGen, GitHub Actions `macos-26`, Python 3 for build scripts.

**Spec:** `docs/superpowers/specs/2026-10-17-m2-video-page-design.md`. Screens: `docs/official-app-reference.md` and the images in `local/official-app-reference/` (read both before any UI task; numbers like "(05)" below are screenshot numbers).

## Global Constraints

- BiliCore is Foundation-only, no third-party packages, Swift 5 language mode, and must pass `swift test --package-path ios/Packages/BiliCore` on Windows and macOS.
- App target: Swift 5 mode, SwiftUI, no third-party dependencies, iOS 26 deployment target.
- UI text is Simplified Chinese, copied from the screenshots where they show it.
- Look: 100% the official app; no liquid glass. Pink accent `#FB7299`. Colours and sizes come from `Theme` (Task 7), never literals in views.
- Never commit secrets, cookies, signed playurl responses, or anything under `logs/` or `local/`. Test fixtures use invented names, ids, text and URLs.
- No code copied from PiliPlus (GPL-3.0) or ATV-Bilibili-demo; read them for endpoints and formats only. The one exception is files, not code: PiliPlus's coin dialog PNGs and icon font, committed in `ios/Resources/Borrowed/` (Task 7; KaiC's call).
- Never log cookie values, SESSDATA, bili_jct/csrf, access tokens or app secrets.
- Bilibili's app key and secret come only from the `BILI_APP_KEYS` GitHub secret at build time (Task 19).
- Code that hands a view to a system controller (PiP, rotation, sheets, share sheet, panels over the rotated player) needs a simulator test that performs that transition. Never make a hosting controller a child of a system controller whose views it may move.
- Comments: why, not what; match the surrounding density.
- Work on branch `m2` (create from `main` at the start). Push after each task. App tasks are verified by the compile check on `m2`:
  `git push origin m2`, then `gh run list --branch m2 --workflow "iOS compile check" --limit 1`, then `gh run watch <id> --exit-status`, then `gh run download <id> -n simulator-screenshots -D <scratchpad>/shots-task<N>` and look at every screenshot the task added, side by side with its reference image.
- A TestFlight build only from `main` after its compile check is green: `git checkout main && git merge --ff-only m2 && git push origin main`, wait for green, then `python scripts/testflight.py start` and `python scripts/testflight.py watch <id>` in the background.
- Every new demo screen is added to the `shoot` list in `.github/workflows/ios-compile.yml` as `shoot <nn>-<name> <seconds> -DemoData YES -DemoScreen <name>`.

## Review Focus

1. A logged-out user, or one whose login expired mid-session (server code -101), taps an action, sends a danmaku, opens 添加屏蔽词 or posts a comment: expect the login screen, no request sent with an empty `csrf`, and the button state rolled back. Tests: Task 1 `testPostWithoutCSRFCookieThrowsWithoutSending`, Task 21 `testExpiredLoginRollsBackAndAsksForLogin`.
2. Seeking back and forth across 6-minute segment boundaries, or seeking repeatedly: danmaku must neither repeat nor show stale. Test: Task 5 `testSeekBackReemitsOnceAndJumpSkips`.
3. A 合集 with several sections, a multi-part video, and the last episode: autoplay must find the current item by cid, walk sections in order and stop at the end. Test: Task 3 `testAutoplayWalksSectionsAndStopsAtTheEnd`.
4. Resume data for another part, within 5 s of the end, or `-1` (finished): start at 0. Test: Task 3 `testResumeIgnoresOtherPartsTheEndAndFinished`.
5. Comment and danmaku text with `&`, `+`, `=`, `!'()*`, emoji (surrogate pairs) and Chinese: forms must send it unchanged and rich text must split runs on character boundaries; unknown `[token]`s stay text. Tests: Task 1 `testFormEncodingKeepsReservedCharactersAndEmoji`, Task 17 `testRunsKeepEmojiAndUnknownTokens`.

---

## File Structure

BiliCore (`ios/Packages/BiliCore/`):

| Path | Responsibility |
|---|---|
| `Sources/BiliAPI/HTTP.swift` | `HTTPRequest` gains `method` and `body` |
| `Sources/BiliAPI/BiliClient.swift` | shared request path; `post`, `getData`, host parameter |
| `Sources/BiliAPI/FormEncoding.swift` | `application/x-www-form-urlencoded` bodies |
| `Sources/BiliAPI/VideoModels.swift`, `BiliClient+Video.swift` | view detail, player info, online count, related, heartbeat, watch later |
| `Sources/BiliAPI/BiliClient+Danmaku.swift` | segments, block rules, posting |
| `Sources/BiliAPI/ActionModels.swift`, `BiliClient+Actions.swift` | relation, card, like, triple, coin, favourites, share, follow, tags |
| `Sources/BiliAPI/CommentModels.swift`, `BiliClient+Comments.swift`, `RichText.swift` | comments, threads, posting, emotes, rich-text runs |
| `Sources/BiliAPI/FeedModels.swift`, `BiliClient+Feed.swift` | 推荐 feed, history |
| `Sources/BiliAPI/AppSigner.swift`, `BiliClient+App.swift` | APP signing, TV login, dislike |
| `Sources/Danmaku/` | protobuf reader, elements, segments, filters, timeline, lanes, midHash |
| `Sources/AppLogic/` | counts and times, gestures, resume, quality, autoplay, heartbeat schedule, history grouping |

App (`ios/Sources/App/`):

| Path | Responsibility |
|---|---|
| `Shared/Theme.swift`, `Shared/BorrowedIcon.swift`, `Shared/RemoteImage.swift`, `Shared/Toast.swift` | tokens, borrowed glyphs/art, image cache, toasts |
| `Player/PlayerHostView.swift`, `Player/PlayerSurface.swift` | `AVPlayerLayer` view, PiP, mirror, fit |
| `Player/OrientationController.swift`, `Player/DeviceControls.swift`, `Player/PlayerGestureView.swift`, `Player/FrameCapture.swift` | full screen states, brightness/volume, gestures, screenshot |
| `Player/Chrome/*.swift` | portrait, landscape and 竖屏 chrome, progress bar, HUDs, end screens |
| `Player/Panels/*.swift` | side panel container, 清晰度, 倍速, ⋮ |
| `Danmaku/*.swift` | renderer, controller, settings panel, block words, send bar |
| `VideoPage/*.swift` | route, model, page view, intro tab, actions, dialogs, sheets, related |
| `Comments/*.swift` | list, thread, row, rich text, composer, emotes, pictures |
| `Home/HomeView.swift`, `Home/FeedModel.swift`, `Home/FeedCard.swift` | 首页 |
| `History/HistoryView.swift`, `History/HistoryModel.swift` | 历史记录 |
| `Account/AppTokenStore.swift`, `Account/TVLoginSheet.swift` | app token |
| `DebugSupport/DemoTransport.swift`, `DebugSupport/DemoFixtures.swift` | demo data for screenshots and app tests |

Removed: `Player/PlayerScreen.swift`, `Player/VideoPlayerView.swift`, `Tests/AppTests/FullScreenTests.swift` (Task 9).

Borrowed files: `ios/Resources/Borrowed/` (16 files from PiliPlus). Build script: `tools/write_app_keys.py` and `tools/test_write_app_keys.py`.

---

# Build A: the player

### Task 1: POST requests, form bodies and raw GETs in BiliClient

**Files:**
- Modify: `ios/Packages/BiliCore/Sources/BiliAPI/HTTP.swift`, `Sources/BiliAPI/BiliClient.swift`, `Sources/BiliAPI/BiliError.swift`, `Sources/DevLog/Redactor.swift`
- Create: `ios/Packages/BiliCore/Sources/BiliAPI/FormEncoding.swift`
- Test: `ios/Packages/BiliCore/Tests/BiliAPITests/PostTests.swift`, `Tests/DevLogTests/RedactorTests.swift`

**Interfaces:**
- Produces:
  - `HTTPRequest.method: String` (default `"GET"`), `HTTPRequest.body: Data?` (default nil); `URLSessionHTTPTransport` sends both.
  - `FormEncoding.encode(_ fields: [String: String]) -> Data` (keys sorted, RFC 3986 unreserved characters kept, everything else percent-encoded as UTF-8, space as `%20`).
  - In `BiliClient` (all `public`):
    - `func get<T: Decodable>(_ path: String, query: [String: String], signed: Bool, host: String = BiliClient.api) async throws -> T` (envelope checked; existing private `get` becomes the shared path).
    - `func getData(_ path: String, query: [String: String], signed: Bool, host: String = BiliClient.api) async throws -> Data` (raw body, status checked).
    - `func post<T: Decodable>(_ path: String, form: [String: String], referer: String? = nil, host: String = BiliClient.api) async throws -> T`
    - `func post(_ path: String, form: [String: String], referer: String? = nil, host: String = BiliClient.api) async throws` (checks `code == 0` only; `data` may be null).
    - `static let api = "https://api.bilibili.com"` (now public), `var csrf: String? { cookies.value("bili_jct") }`.
  - `BiliError.needsLogin: Bool` (true for `.api(code: -101, _)`).
  - `BiliError.userMessage` for `.api(code: -352, _)` and `.api(code: -412, _)` is "请求过于频繁，请稍后再试" (spec section 6).
- POST headers: `User-Agent` (existing), `Referer` (given, else `BiliClient.referer`), `Origin: https://www.bilibili.com`, `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`, `Cookie`. The form always gets `csrf`; with no `bili_jct` cookie the call throws `.api(code: -101, message: "账号未登录")` before sending.

- [ ] **Step 1: Create branch `m2` from `main`.** `git checkout -b m2`
- [ ] **Step 2: Write the failing tests** in `PostTests.swift` (reuse `FakeHTTP` from `BiliClientTests.swift`; extend it to record `method` and `body` and to route by path for POST too):

```swift
func testPostSendsFormWithCSRFAndBrowserHeaders() async throws {
    let http = FakeHTTP(); http.routes["/x/v2/history/toview/add"] = (200, #"{"code":0,"message":"0","data":null}"#)
    let client = makeClient(http, cookies: ["bili_jct": "TOKEN", "SESSDATA": "s"])
    try await client.post("/x/v2/history/toview/add", form: ["aid": "1"], referer: "https://www.bilibili.com/video/BV1")
    let request = try XCTUnwrap(http.requests(to: "/x/v2/history/toview/add").first)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(String(decoding: request.body ?? Data(), as: UTF8.self), "aid=1&csrf=TOKEN")
    XCTAssertEqual(request.headers["Origin"], "https://www.bilibili.com")
    XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/video/BV1")
    XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded; charset=UTF-8")
}

func testPostWithoutCSRFCookieThrowsWithoutSending() async {
    let http = FakeHTTP()
    let client = makeClient(http, cookies: ["SESSDATA": "s"])
    do { try await client.post("/x/v2/history/toview/add", form: ["aid": "1"]); XCTFail("expected -101") }
    catch let error as BiliError { XCTAssertTrue(error.needsLogin) } catch { XCTFail("\(error)") }
    XCTAssertTrue(http.requests.current.isEmpty)
}

func testRiskControlCodesReadAsTooFrequent() {
    XCTAssertEqual(BiliError.api(code: -352, message: "").userMessage, "请求过于频繁，请稍后再试")
}

func testPostErrorCodeThrowsTheServerMessage() async {
    // route returns {"code":34002,"message":"不能给自己点赞"} → BiliError.api(code: 34002, message: "不能给自己点赞")
}

func testFormEncodingKeepsReservedCharactersAndEmoji() {
    let body = String(decoding: FormEncoding.encode(["message": "a&b=c+d !'()* 你好😀", "b": "1"]), as: UTF8.self)
    XCTAssertEqual(body, "b=1&message=a%26b%3Dc%2Bd%20%21%27%28%29%2A%20%E4%BD%A0%E5%A5%BD%F0%9F%98%80")
}

func testGetDataReturnsTheRawBodyAndHostCanChange() async throws {
    // routes["/x/v2/dm/web/seg.so"] = (200, "\u{08}\u{01}") → getData returns Data([0x08, 0x01]);
    // a get with host "https://account.bilibili.com" hits that host (assert request.url.host)
}
```

Redactor test in `RedactorTests.swift`:

```swift
func testSignIsRedactedButWordsContainingSignAreNot() {
    let line = Redactor.text("https://app.bilibili.com/x?appkey=k&sign=abc123&design=ok")
    XCTAssertFalse(line.contains("abc123")); XCTAssertTrue(line.contains("design=ok"))
}
```

(Use the Redactor's existing public entry point for free text; if it is named differently, use that name.)

- [ ] **Step 3: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter "PostTests|RedactorTests"` → compile errors / failures.
- [ ] **Step 4: Implement.** One private `send(method:path:query:signed:host:form:referer:retried:) -> HTTPResponse` used by `get`, `getData` and `post`, keeping the existing 412 retry and logging (log path, status, code, ms; never the body). `sign` joins the Redactor's secret names as an exact name.
- [ ] **Step 5: Run the whole package.** `swift test --package-path ios/Packages/BiliCore` → all pass.
- [ ] **Step 6: Commit and push.** `git commit -m "BiliClient: POST with form bodies and csrf, raw GETs, other hosts"`; `git push -u origin m2`.

### Task 2: Video detail, player info, related, online count, heartbeat, watch later

**Files:**
- Create: `ios/Packages/BiliCore/Sources/BiliAPI/VideoModels.swift`, `Sources/BiliAPI/BiliClient+Video.swift`
- Modify: `Sources/BiliAPI/Models.swift` (`PlayURLInfo`)
- Test: `Tests/BiliAPITests/VideoAPITests.swift`, `Tests/BiliAPITests/Fixtures.swift`

**Interfaces:**
- Consumes: Task 1 `get`, `post`.
- Produces (all `public`, `Sendable`, `Equatable`, decoded with the `AnyKey`/`first` helpers):
  - `struct VideoOwner { mid: Int64; name: String; face: String }`
  - `struct VideoStat { view, danmaku, reply, favorite, coin, share, like: Int64 }`
  - `struct DescPart { text: String; mentionMid: Int64? }` (`desc_v2`: `type` 2 → mention with `biz_id`)
  - `struct SeasonEpisode { aid: Int64; bvid: String; cid: Int64; title: String; cover: String; duration: Int; pubdate: Int64; views: Int64; danmaku: Int64 }` (cover, duration, pubdate and counts from `arc`)
  - `struct SeasonSection { id: Int64; title: String; episodes: [SeasonEpisode] }`
  - `struct UgcSeason { id: Int64; title: String; intro: String; sections: [SeasonSection] }`
  - `struct StaffMember { mid: Int64; title: String; name: String; face: String }`
  - `struct VideoDetail { bvid; aid; title; cover (pic); pubdate: Int64; duration: Int; desc: String; descParts: [DescPart]; copyright: Int; owner: VideoOwner; stat: VideoStat; pages: [VideoPage]; season: UgcSeason?; staff: [StaffMember]; width: Int; height: Int; honor: String?; redirectURL: String? }` with `var isVertical: Bool` (height > width after swapping when `dimension.rotate == 1`). `honor` = the first `honor_reply.honor[].desc` if present (the 活动 tag; nil otherwise).
  - `struct Chapter { from: Double; to: Double; title: String }`
  - `struct PlayerInfo { lastPlayCid: Int64; chapters: [Chapter] }` (chapters only when the first `view_points` entry has `type == 2`)
  - `struct VideoCard { aid: Int64; bvid: String; cid: Int64; title: String; cover: String; duration: Int; ownerMid: Int64; ownerName: String; views: Int64; danmaku: Int64; likes: Int64 }`
  - `PlayURLInfo.lastPlayTimeMs: Int64` (`last_play_time`, default 0), `PlayURLInfo.lastPlayCid: Int64` (default 0); the memberwise init gains both with default 0.
  - `BiliClient`:
    - `videoDetail(bvid: String) async throws -> VideoDetail`: GET `/x/web-interface/wbi/view` signed, `bvid`
    - `playerInfo(bvid: String, cid: Int64) async throws -> PlayerInfo`: GET `/x/player/wbi/v2` signed
    - `onlineCount(aid: Int64, bvid: String, cid: Int64) async throws -> String`: GET `/x/player/online/total`, returns `data.total` verbatim
    - `related(bvid: String) async throws -> [VideoCard]`: GET `/x/web-interface/archive/related`; drops items without a bvid or with a `redirect_url`
    - `heartbeat(bvid: String, cid: Int64, playedTime: Int) async throws`: POST `/x/click-interface/web/heartbeat` form `bvid`, `cid`, `type=3`, `played_time`
    - `addToWatchLater(aid: Int64) async throws`: POST `/x/v2/history/toview/add` form `aid`

- [ ] **Step 1: Add fixtures** `viewDetail` (a two-section 合集 with three episodes, two pages, `staff` empty, `dimension` 1080×1920 with `rotate` 0, `honor_reply` with one 活动 entry, `desc_v2` with a text part and a mention), `playerV2` (`last_play_cid`, three `view_points` of `type` 2), `related` (two cards, one with `redirect_url`), `online` (`{"total":"1.2万+"}`), `playURLResume` (`last_play_time` 65000, `last_play_cid` 137649199). Invented values only.
- [ ] **Step 2: Write the failing tests:**

```swift
func testVideoDetailDecodesSeasonStaffStatsAndShape() async throws {
    let detail = try await client.videoDetail(bvid: "BV1GJ411x7h7")
    XCTAssertEqual(detail.season?.sections.map(\.episodes.count), [2, 1])
    XCTAssertEqual(detail.season?.sections[0].episodes[1].cid, 137649300)
    XCTAssertEqual(detail.stat.like, 9131)
    XCTAssertTrue(detail.isVertical)
    XCTAssertEqual(detail.honor, "活动")
    XCTAssertEqual(detail.descParts.last?.mentionMid, 42)
    XCTAssertNotNil(fakeHTTP.query(of: fakeHTTP.requests(to: "/x/web-interface/wbi/view")[0])["w_rid"])
}
func testPlayerInfoKeepsChaptersOnlyForType2() async throws  // 3 chapters; a fixture with type 1 gives []
func testRelatedDropsRedirectedItems() async throws          // 2 in → 1 out
func testOnlineCountIsTheDisplayString() async throws        // "1.2万+"
func testHeartbeatFormFields() async throws                  // body "bvid=BV1&cid=2&csrf=T&played_time=-1&type=3"
func testPlayURLCarriesResumeFields() throws                 // decode playURLResume: 65000, 137649199; old fixture: 0, 0
```

- [ ] **Step 3: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter VideoAPITests`
- [ ] **Step 4: Implement** the models and calls. Decoding of single elements uses the existing `Lossy` wrapper for arrays, so one odd related item or episode does not fail the list.
- [ ] **Step 5: Run the whole package**, all pass.
- [ ] **Step 6: Commit and push.** `git commit -m "BiliAPI: video detail, player info, related, online count, heartbeat, watch later"`

### Task 3: AppLogic target: formats, gestures, resume, quality, autoplay, heartbeat schedule

**Files:**
- Modify: `ios/Packages/BiliCore/Package.swift` (target `AppLogic` depending on `BiliShared`; test target `AppLogicTests`; add `AppLogic` to the `BiliCore` product)
- Create: `Sources/AppLogic/CountFormat.swift`, `TimeFormat.swift`, `GestureMath.swift`, `ResumePoint.swift`, `QualityRules.swift`, `Autoplay.swift`, `HeartbeatSchedule.swift`
- Test: `Tests/AppLogicTests/*.swift` (one file per source file)

**Interfaces (all `public`):**
- `enum CountFormat { static func short(_ n: Int64) -> String }`: under 10 000 as is; under 100 000 000 as `万` with one decimal, `.0` dropped; above as `亿` likewise.
- `enum TimeFormat`:
  - `static func clock(_ seconds: Double) -> String`: `"03:15"`, `"1:02:03"` from an hour.
  - `static func pair(_ position: Double, _ duration: Double) -> String`: `"00:01/03:15"`.
  - `static func publish(_ unix: Int64, timeZone: TimeZone = .current) -> String`: `"2026年10月11日 21:05"`.
  - `static func relative(_ unix: Int64, now: Date, timeZone: TimeZone = .current) -> String`: `刚刚` (<60 s), `N分钟前`, `N小时前` (<24 h), `昨天 HH:mm`, `MM-dd` (same year), `yyyy-MM-dd`.
- `enum GestureMath`:
  - `static let seekSecondsPerWidth = 90.0`, `static let axisLockDistance = 10.0`, `static let edgeInset = 25.0`.
  - `enum Axis { case horizontal, vertical }`; `static func axis(dx: Double, dy: Double) -> Axis?` (nil until `hypot(dx, dy) >= 10`, then whichever moved more; ties are horizontal).
  - `static func seekTarget(start: Double, dx: Double, width: Double, duration: Double) -> Double` (clamped to `0...duration`).
  - `static func level(start: Double, dy: Double, height: Double) -> Double` (upward drag raises; full height = 1.0; clamped `0...1`).
- `enum ResumePoint { static func start(lastPlayTimeMs: Int64, lastPlayCid: Int64, cid: Int64, duration: Double) -> Double }`: the saved second when `lastPlayCid == cid`, `lastPlayTimeMs > 0` and more than 5 s before the end; otherwise 0.
- `enum QualityRules`:
  - `static func needsVip(_ qn: Int) -> Bool` (`qn >= 112`).
  - `static func auto(offered: [Int], isVip: Bool) -> Int?` (highest offered the account can play).
- `struct PlayItem: Hashable, Sendable { bvid: String; cid: Int64 }`
- `enum LoopMode: String, CaseIterable, Sendable { case single, list, none }`
- `enum NextStep: Equatable { case replay, play(PlayItem), stop }`
- `enum Autoplay { static func next(after current: PlayItem, parts: [PlayItem], episodes: [PlayItem], autoplay: Bool, loop: LoopMode) -> NextStep }`. `episodes` is every 合集 episode of every section in order. Rules: `.single` → `.replay`. Otherwise, if `autoplay` or `.list`: the next part of the same bvid, else the episode after the one whose cid matches `current.cid`, or failing that the one whose bvid matches. With `.list` at the very end: the first part or episode (or `.replay` when there is only one item). Otherwise `.stop`.
- `struct HeartbeatSchedule { init(interval: Double = 15); mutating func tick(position: Double, playing: Bool) -> Int?; mutating func mark(position: Double) -> Int; static let finished = -1 }`. `tick` returns `Int(position)` when playing and `position - baseline >= interval`, then moves the baseline. `mark` (pause, seek done, part change, leaving) returns `Int(position)` and moves the baseline.

- [ ] **Step 1: Write the failing tests** (selection; one test per bullet above):

```swift
func testShortCounts() {
    XCTAssertEqual(CountFormat.short(9131), "9131"); XCTAssertEqual(CountFormat.short(10_000), "1万")
    XCTAssertEqual(CountFormat.short(37_000), "3.7万"); XCTAssertEqual(CountFormat.short(82_838_000), "8283.8万")
    XCTAssertEqual(CountFormat.short(120_000_000), "1.2亿")
}
func testClockAndPair() { XCTAssertEqual(TimeFormat.pair(1, 195), "00:01/03:15"); XCTAssertEqual(TimeFormat.clock(3723), "1:02:03") }
func testRelativeTimes()   // now fixed; 30 s → 刚刚, 5 min → 5分钟前, 3 h → 3小时前, yesterday 21:05 → 昨天 21:05, same year → 10-01, last year → 2025-10-01 (UTC+8)
func testAxisLocksAfterTenPoints() { XCTAssertNil(GestureMath.axis(dx: 6, dy: 6)); XCTAssertEqual(GestureMath.axis(dx: 8, dy: -9), .vertical) }
func testSeekIs90SecondsPerWidthAndClamped() {
    XCTAssertEqual(GestureMath.seekTarget(start: 100, dx: 200, width: 400, duration: 600), 145)
    XCTAssertEqual(GestureMath.seekTarget(start: 10, dx: -400, width: 400, duration: 600), 0)
}
func testLevelUpRaisesAndClamps() { XCTAssertEqual(GestureMath.level(start: 0.5, dy: -100, height: 400), 0.75); XCTAssertEqual(GestureMath.level(start: 0.9, dy: -400, height: 400), 1) }
func testResumeIgnoresOtherPartsTheEndAndFinished() {
    XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_000, lastPlayCid: 1, cid: 1, duration: 200), 65)
    XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 65_000, lastPlayCid: 2, cid: 1, duration: 200), 0)
    XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: 196_000, lastPlayCid: 1, cid: 1, duration: 200), 0)
    XCTAssertEqual(ResumePoint.start(lastPlayTimeMs: -1, lastPlayCid: 1, cid: 1, duration: 200), 0)
}
func testAutoQualityRespectsVip() { XCTAssertEqual(QualityRules.auto(offered: [120, 116, 80, 64], isVip: false), 80); XCTAssertEqual(QualityRules.auto(offered: [120, 80], isVip: true), 120) }
func testAutoplayWalksSectionsAndStopsAtTheEnd() {
    let a = PlayItem(bvid: "A", cid: 1), b = PlayItem(bvid: "B", cid: 2), c = PlayItem(bvid: "C", cid: 3)
    XCTAssertEqual(Autoplay.next(after: a, parts: [a], episodes: [a, b, c], autoplay: true, loop: .none), .play(b))
    XCTAssertEqual(Autoplay.next(after: c, parts: [c], episodes: [a, b, c], autoplay: true, loop: .none), .stop)
    XCTAssertEqual(Autoplay.next(after: c, parts: [c], episodes: [a, b, c], autoplay: false, loop: .list), .play(a))
    XCTAssertEqual(Autoplay.next(after: b, parts: [b], episodes: [a, b, c], autoplay: false, loop: .none), .stop)
    XCTAssertEqual(Autoplay.next(after: b, parts: [b], episodes: [a, b, c], autoplay: true, loop: .single), .replay)
}
func testAutoplayPrefersTheNextPart()   // parts [A#1, A#2], current A#1 → .play(A#2) even with episodes present
func testHeartbeatEvery15SecondsOfPlaybackAndOnMarks() {
    var s = HeartbeatSchedule()
    XCTAssertNil(s.tick(position: 14, playing: true)); XCTAssertEqual(s.tick(position: 15, playing: true), 15)
    XCTAssertNil(s.tick(position: 40, playing: false)); XCTAssertEqual(s.mark(position: 40), 40)
    XCTAssertNil(s.tick(position: 54, playing: true))
}
```

- [ ] **Step 2: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter AppLogicTests`
- [ ] **Step 3: Implement** the target and files. Calendar maths uses `Calendar(identifier: .gregorian)` with the given time zone.
- [ ] **Step 4: Run the whole package**, all pass.
- [ ] **Step 5: Commit and push.** `git commit -m "AppLogic: formats, gesture maths, resume, quality, autoplay order, heartbeat schedule"`

### Task 4: Danmaku target: protobuf reader, elements, segments, segment fetch

**Files:**
- Modify: `ios/Packages/BiliCore/Package.swift` (target `Danmaku` depending on `BiliShared`; `BiliAPI` gains a dependency on `Danmaku`; test target `DanmakuTests`; product gains `Danmaku`)
- Create: `Sources/Danmaku/ProtobufReader.swift`, `Sources/Danmaku/DanmakuElem.swift`, `Sources/Danmaku/DanmakuSegment.swift`, `Sources/BiliAPI/BiliClient+Danmaku.swift`
- Test: `Tests/DanmakuTests/ProtobufReaderTests.swift`, `Tests/DanmakuTests/SegmentTests.swift`, `Tests/DanmakuTests/ProtobufWriter.swift` (test-only encoder), `Tests/BiliAPITests/DanmakuAPITests.swift`

**Interfaces (all `public`):**
- `struct ProtobufReader { init(_ data: Data); mutating func next() throws -> (field: Int, wireType: Int)?; mutating func varint() throws -> UInt64; mutating func lengthDelimited() throws -> Data; mutating func skip(wireType: Int) throws }` (wire types 0, 1, 2, 5; anything else throws).
- `enum ProtobufError: Error, Equatable { case truncated, badWireType(Int) }`
- `struct DanmakuElem: Sendable, Equatable { id: Int64; progressMs: Int64; mode: Int; fontSize: Int; color: UInt32; midHash: String; content: String; ctime: Int64; weight: Int; pool: Int; idStr: String; attr: Int; colorful: Int; static func decode(_ data: Data) throws -> DanmakuElem }`. Field numbers: 1 id, 2 progress, 3 mode, 4 fontsize, 5 color, 6 midHash, 7 content, 8 ctime, 9 weight, 11 pool, 12 idStr, 13 attr, 24 colorful. Unknown fields are skipped.
- `struct DanmakuSegment: Sendable { elems: [DanmakuElem]; closed: Bool; static func decode(_ data: Data) throws -> DanmakuSegment }` (field 1 repeated elems; field 2 `state`, `closed = state == 1`).
- `enum DanmakuSegments { static let lengthMs: Int64 = 360_000; static func index(forMs ms: Int64) -> Int; static func needed(atMs ms: Int64, loaded: Set<Int>, durationMs: Int64) -> [Int] }`. Index is 1-based. `needed` returns the current segment if missing, plus the next one when within 30 000 ms of the boundary and the video goes on past it.
- `BiliClient.danmakuSegment(cid: Int64, index: Int) async throws -> DanmakuSegment`: `getData` on `/x/v2/dm/web/seg.so` with `type=1`, `oid`, `segment_index`, unsigned. On HTTP 403 or 412 it retries once on `/x/v2/dm/wbi/web/seg.so` signed.

- [ ] **Step 1: Write the test-only `ProtobufWriter`** (varint, length-delimited, fixed32/64 fields) in the test target.
- [ ] **Step 2: Write the failing tests:**

```swift
func testDecodesAnElementAndSkipsUnknownFields() throws {
    var w = ProtobufWriter()
    w.varint(1, 7); w.varint(2, 61_500); w.varint(3, 5); w.varint(4, 25); w.varint(5, 0xFE0302)
    w.string(6, "1a2b3c4d"); w.string(7, "前方高能"); w.varint(9, 8); w.fixed32(99, 1); w.varint(24, 60001)
    let e = try DanmakuElem.decode(w.data)
    XCTAssertEqual(e.progressMs, 61_500); XCTAssertEqual(e.mode, 5); XCTAssertEqual(e.color, 0xFE0302)
    XCTAssertEqual(e.content, "前方高能"); XCTAssertEqual(e.colorful, 60001)
}
func testSegmentWithStateOneIsClosed() throws        // field 2 = 1 → closed; two elems decoded
func testTruncatedInputThrows()                       // cut the last byte → ProtobufError.truncated
func testSegmentIndexIsOneBasedSixMinutes() { XCTAssertEqual(DanmakuSegments.index(forMs: 0), 1); XCTAssertEqual(DanmakuSegments.index(forMs: 360_000), 2) }
func testNeededPrefetchesNearTheBoundaryOnly() {
    XCTAssertEqual(DanmakuSegments.needed(atMs: 10_000, loaded: [], durationMs: 900_000), [1])
    XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [1], durationMs: 900_000), [2])
    XCTAssertEqual(DanmakuSegments.needed(atMs: 335_000, loaded: [1], durationMs: 350_000), [])
}
func testSegmentFetchQueryAndWBIFallback() async throws  // first path 412 → second path signed, decoded elems count
```

- [ ] **Step 3: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter "DanmakuTests|DanmakuAPITests"`
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run the whole package**, all pass.
- [ ] **Step 6: Commit and push.** `git commit -m "Danmaku: protobuf segments decoded in BiliCore, segment fetch"`

### Task 5: Danmaku filters, timeline and lane layout

**Files:**
- Create: `Sources/Danmaku/MidHash.swift`, `Sources/Danmaku/DanmakuFilter.swift`, `Sources/Danmaku/DanmakuTimeline.swift`, `Sources/Danmaku/LaneLayout.swift`
- Test: `Tests/DanmakuTests/FilterTests.swift`, `TimelineTests.swift`, `LaneLayoutTests.swift`

**Interfaces (all `public`):**
- `enum MidHash { static func of(uid: Int64) -> String }`: lower-case hex CRC-32 (IEEE) of the decimal uid string, no leading zeros.
- `struct BlockRule: Sendable, Hashable { enum Kind: Int, Sendable { case keyword = 0, regex = 1, user = 2 }; id: Int64; kind: Kind; filter: String }`
- `struct DanmakuFilterOptions: Sendable, Equatable, Codable { blockFixed, blockScroll, blockColored, blockAdvanced, blockCount, dedupe, hideBottom: Bool; applyRules: Bool = true }` (all others default false).
- `struct DisplayDanmaku: Sendable, Equatable { elem: DanmakuElem; text: String; isOwn: Bool }`
- `enum DanmakuFilter { static func apply(_ elems: [DanmakuElem], options: DanmakuFilterOptions, rules: [BlockRule], ownHash: String?) -> [DisplayDanmaku] }`. Rules, in order:
  1. Modes 7, 8 and 9 are dropped.
  2. Mode 1 or 6 with `blockScroll`, modes 4/5 with `blockFixed`, mode 4 with `hideBottom`, and a non-white colour (`color != 0xFFFFFF`) or `colorful != 0` with `blockColored` are dropped.
  3. With `applyRules`: keyword rules drop on substring match, regex rules case-insensitively (surrounding `/` stripped; a bad pattern is ignored), user rules on `midHash` equality. Own danmaku (`midHash == ownHash`) are never filtered by rules.
  4. With `dedupe`: an element whose content equals one kept within the previous 10 000 ms is merged into it, and the kept one's `text` becomes `"<content> ×N"` once N ≥ 2. With `blockCount`, merged ones (N ≥ 2) are dropped. Ruling: this is what the spec's 计数 (`×N` merge danmaku) means.
  5. Output is sorted by `progressMs`.
- `struct DanmakuTimeline { init(); mutating func add(_ items: [DisplayDanmaku]); mutating func advance(to ms: Int64) -> [DisplayDanmaku]; mutating func seek(to ms: Int64) }`. `advance` returns the items with `progressMs` in `(last, ms]` and moves `last`. A step backwards, or one larger than 1 000 ms, is treated as `seek`: nothing is returned and `last = ms`. Items added later behind `last` are not emitted until a seek brings the playhead before them again.
- `struct LaneLayout { enum Kind { case scroll, top, bottom }; init(lanes: Int, width: Double, scrollDuration: Double, staticDuration: Double = 4); mutating func place(_ kind: Kind, width w: Double, at t: Double) -> Int?; mutating func reset(lanes: Int, width: Double, scrollDuration: Double) }`. Returns the lane (0 = top line; bottom lanes count up from the bottom as `lanes - 1 - i`) or nil when no lane fits. Algorithm for scroll, with `W` the screen width and `D` the scroll duration (a danmaku of width `w` moves at `v = (W + w) / D`): a lane fits when it is empty, or when its last danmaku (start `ti`, width `wi`, speed `vi`) has fully entered, `(t - ti) * vi >= wi`, and the new one cannot catch it before it leaves, `(ti + D - t) * v <= W`. Top and bottom lanes fit when `busyUntil <= t`; `busyUntil = t + staticDuration`. The first fitting lane wins.

- [ ] **Step 1: Write the failing tests:**

```swift
func testMidHashMatchesCRC32() { XCTAssertEqual(MidHash.of(uid: 12345), "cbf53a1c") }   // zlib.crc32(b"12345")
func testTypeAndColourBlocks()            // one elem per mode/colour; each option drops exactly its kind; modes 7/8/9 always dropped
func testRulesKeywordRegexUserAndOwnExempt()
func testDedupeMergesWithinTenSecondsAndCountBlockDropsMerged() {
    // three "哈哈" at 1 000, 5 000, 12 000 ms → dedupe: two items, the first "哈哈 ×2"; with blockCount: only the 12 000 one
}
func testSeekBackReemitsOnceAndJumpSkips() {
    var t = DanmakuTimeline(); t.add(items(at: [500, 1_500, 2_500]))
    XCTAssertEqual(t.advance(to: 600).count, 1); XCTAssertEqual(t.advance(to: 1_600).count, 1)
    t.seek(to: 0); XCTAssertEqual(t.advance(to: 600).count, 1)
    XCTAssertEqual(t.advance(to: 3_000).count, 0)   // a 2 400 ms jump is a seek
}
func testScrollLaneWaitsUntilTheLastOneHasEntered()   // W 400, D 8, w 100 at t 0 in lane 0; second at t 0.5 → lane 1; at t 2.0 → lane 0
func testFastLongDanmakuDoesNotCatchASlowShortOne()   // W 400, D 8: short w 20 at t 0 (lane 0); long w 400 at t 0.5 has entered-room but (8 - 0.5) × 100 > 400 → lane 1
func testStaticLanesFromTheirEdgesAndDropWhenFull() // 2 lanes: top, top → 0, 1; third top → nil; bottom → lane 1 counted from the bottom
func testHeavySegmentFiltersAndLaysOutQuickly()    // 20 000 elems, all options on, 30 lanes: filter + place all within 1.0 s (measured with Date)
```

(The midHash expectation is CRC-32 of the ASCII string `"12345"`: compute it with Python's `zlib.crc32(b"12345")` while writing the test and put the hex literal in.)

- [ ] **Step 2: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter DanmakuTests`
- [ ] **Step 3: Implement.** CRC-32 table built once. The heavy-segment test guards against quadratic scans: dedupe keeps a dictionary of content → last kept index.
- [ ] **Step 4: Run the whole package**, all pass.
- [ ] **Step 5: Commit and push.** `git commit -m "Danmaku: filters, merge, timeline and collision-free lanes"`

### Task 6: Danmaku block rules and sending (API)

**Files:**
- Modify: `Sources/BiliAPI/BiliClient+Danmaku.swift`
- Test: `Tests/BiliAPITests/DanmakuAPITests.swift`

**Interfaces (all `public`):**
- `BiliClient.danmakuBlockRules() async throws -> [BlockRule]`: GET `/x/dm/filter/user` → `data.rule[]` (`id`, `type`, `filter`).
- `BiliClient.addBlockRule(_ kind: BlockRule.Kind, filter: String) async throws -> BlockRule`: POST `/x/dm/filter/user/add` form `type`, `filter`.
- `BiliClient.deleteBlockRule(id: Int64) async throws`: POST `/x/dm/filter/user/del` form `ids`.
- `struct DanmakuDraft: Sendable { cid: Int64; bvid: String; text: String; mode: Int; fontSize: Int; color: UInt32; gradient: Bool; progressMs: Int64 }`
- `BiliClient.postDanmaku(_ draft: DanmakuDraft) async throws -> Int64`: POST `/x/v2/dm/post` with form `type=1`, `oid`, `bvid`, `msg`, `mode`, `fontsize`, `color` (decimal), `progress`, `rnd` (current time in microseconds from the client's clock), `pool=0`, and `colorful=60001` only when `gradient`. Returns `data.dmid`. Referer: `https://www.bilibili.com/video/<bvid>`.

- [ ] **Step 1: Write the failing tests:**

```swift
func testBlockRulesDecodeKinds() async throws            // three rules, kinds keyword/regex/user
func testAddAndDeleteBlockRuleForms() async throws       // add body "csrf=T&filter=%E5%89%A7%E9%80%8F&type=0"; del body "csrf=T&ids=9"
func testPostDanmakuForm() async throws {
    // client clock 1_702_204_169 s → rnd "1702204169000000"; gradient false → no colorful field
    // body contains "color=16646914", "fontsize=25", "mode=1", "msg=...", "oid=2", "pool=0", "progress=61500", "type=1"
    // returns dmid 777 from {"code":0,"data":{"dmid":777}}
}
func testPostDanmakuGradientAddsColorful() async throws
```

- [ ] **Step 2: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter DanmakuAPITests`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole package**, all pass.
- [ ] **Step 5: Commit and push.** `git commit -m "BiliAPI: danmaku block rules and sending"`

### Task 7: App plumbing: borrowed assets, theme, images, demo data

**Files:**
- Create: `ios/Resources/Borrowed/` (16 copied files), `ios/Sources/App/Shared/Theme.swift`, `ios/Sources/App/Shared/BorrowedIcon.swift`, `ios/Sources/App/Shared/RemoteImage.swift`, `ios/Sources/App/Shared/Toast.swift`, `ios/Sources/App/DebugSupport/DemoTransport.swift`, `ios/Sources/App/DebugSupport/DemoFixtures.swift`, `ios/Tests/AppTests/ImageLoaderTests.swift`, `ios/Tests/AppTests/BorrowedIconTests.swift`
- Modify: `ios/project.yml` (`NSPhotoLibraryAddUsageDescription: 用于把视频截图保存到相册。`), `ios/Sources/App/AppEnvironment.swift` (demo transport when `-DemoData YES`, `#if DEBUG`)

**Interfaces:**
- Borrowed files: copy `assets/fonts/custom_icon.ttf` and the 15 files in `assets/images/paycoins/` from the local clone `D:\Repos\Apps\PiliPlus` into `ios/Resources/Borrowed/`, keeping their names, and commit them. The clone must be at commit `bb2d86ca25d2d4ad9ed42addf37990ae8931c098`; check with `git -C D:\Repos\Apps\PiliPlus rev-parse HEAD`.
- `enum Theme` with static tokens:
  - Colours: `pink` (#FB7299), `pinkTint` (pink at 12%), `text` (#18191C), `secondaryText` (#9499A0), `pageGrey` (#F1F2F3), `divider` (#E3E5E7), `panel` (#000000 at 92%), `panelCard` (#2B2B2E), `panelText` (white), `panelSecondary` (white at 60%), `link` (#008AC5).
  - `Metrics`: `gutter` 16, `cardRadius` 8, `pillHeight` 32.
  - Values are from the screenshots; the implementer corrects them by sampling the images.
- `enum BorrowedIcon: CaseIterable { case danmakuOn, danmakuOff, danmakuSettings }`:
  - `var image: Image` draws the glyph from the registered `custom_icon.ttf`, using the code points from PiliPlus's `lib/common/widgets/custom_icon.dart` (`dm_on`, `dm_off`, `dm_settings`; code points are facts).
  - Falls back to SF Symbols `text.bubble`, `text.bubble.slash`, `gearshape` when the font is missing.
  - `static func registerFont()` (CTFontManager; called at launch) and `static func art(_ name: String) -> UIImage?` load the paycoins PNGs from the bundle.
- `actor ImageLoader`:
  - `static let shared`.
  - `init(fetch: @escaping @Sendable (URL) async throws -> Data = ImageLoader.network)`.
  - `func image(for url: URL) async -> UIImage?` uses an `NSCache` memory cache plus a disk cache in `Caches/images/<sha256(url)>`. Network requests carry `Referer: https://www.bilibili.com/`.
  - Protocol-relative and `http://` URLs are upgraded to `https://`.
- `struct RemoteImage: View { init(_ url: String?, contentMode: ContentMode = .fill) }`: a grey placeholder until loaded.
- `struct Toast`: one-line black capsule at the bottom for 2 s, presented with `.toast(_ message: Binding<String?>)`.
- `final class DemoTransport: HTTPTransport` (`#if DEBUG`) answers from `DemoFixtures.response(for: URL, method: String) -> (Int, Data)`. Every endpoint a later task adds gets a demo fixture in that task.

- [ ] **Step 1: Write the failing tests.**

  `ImageLoaderTests`:
  - `testSecondRequestComesFromCache`: the fetch counter stays 1.
  - `testProtocolRelativeURLsBecomeHTTPS`.

  `BorrowedIconTests`:
  - `testBorrowedFontAndArtLoad`: after `registerFont()` the font is found, and `art("ic_coins_one")` is non-nil.
  - `testFallsBackWhenTheFontIsMissing`: the fallback path returns a non-nil image.
- [ ] **Step 2: Copy the borrowed files and implement** everything listed. Launch calls `BorrowedIcon.registerFont()` in `BiliNativeApp.init`.
- [ ] **Step 3: Push and watch the compile check** (Global Constraints). Expected: green, and the app tests pass.
- [ ] **Step 4: Commit and push** (if not already). `git commit -m "App plumbing: borrowed coin art and icon font, theme, image cache, demo transport"`

### Task 8: Player surface, PiP, full-screen orientation, device controls, gestures

**Files:**
- Create: `ios/Sources/App/Player/PlayerHostView.swift`, `PlayerSurface.swift`, `OrientationController.swift`, `DeviceControls.swift`, `PlayerGestureView.swift`, `FrameCapture.swift`, `ios/Sources/App/AppDelegate.swift`, `ios/Tests/AppTests/PlayerTransitionTests.swift`
- Modify: `ios/Sources/App/BiliNativeApp.swift` (`@UIApplicationDelegateAdaptor(AppDelegate.self)`)

**Interfaces:**
- `final class PlayerHostView: UIView`:
  - `layerClass` is `AVPlayerLayer`; `var player: AVPlayer?`.
  - `var fit: FitMode` sets `videoGravity`: `.fit` → aspect, `.fill` → aspectFill, `.stretch` → resize; `.ratio16x9` and `.ratio4x3` letterbox the layer frame to that ratio.
  - `var mirrored: Bool` (a horizontal flip transform on the player layer only).
  - `let danmakuContainer: UIView` (above video, under controls, `isUserInteractionEnabled = false`).
  - `let gestureView: PlayerGestureView`.
  - `private(set) var pip: AVPictureInPictureController?` (created when the layer has a player; `canStartPictureInPictureAutomaticallyFromInline = true`).
  - `func startPiP()`.
- `enum FitMode: String, CaseIterable { case fit, fill, stretch, ratio16x9, ratio4x3 }` with `label` 适应, 填充, 拉伸, 16:9, 4:3.
- `struct PlayerSurface: UIViewRepresentable` with `player`, `fit`, `mirrored`, `allowsLevelGestures: Bool`, `onGesture: (PlayerGestureEvent) -> Void`, `danmaku: UIView?` (the renderer view from Task 12, added into `danmakuContainer`).
- `@MainActor @Observable final class OrientationController`:
  - `enum Presentation: Equatable { case inline, landscape, vertical }`; `static let shared`.
  - `private(set) var presentation: Presentation`; `var locked: Bool`; `var videoIsVertical: Bool`.
  - `var mask: UIInterfaceOrientationMask`: portrait when inline or vertical; `.landscape` in landscape.
  - `func enterLandscape()`, `func enterVertical()`, `func exitToInline()`.
  - `func deviceOrientationChanged(_ orientation: UIDeviceOrientation)` applies the spec 4.3 rules:
    - Landscape while inline and horizontal → `enterLandscape()`.
    - Portrait while in landscape → `exitToInline()`.
    - Vertical videos and `locked` ignore turning.
    - Starts observing in `begin()`, stops in `end()` (called by the page on appear/disappear).
  - Uses `windowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))` and `setNeedsUpdateOfSupportedInterfaceOrientations()` on the root controller.
- `AppDelegate: UIApplicationDelegate`: `application(_:supportedInterfaceOrientationsFor:)` returns `OrientationController.shared.mask`.
- `@MainActor enum DeviceControls`:
  - `static var brightness: Double { get set }` (the key window scene's screen).
  - `static func volume() -> Double`, `static func setVolume(_ value: Double)` (a hidden `MPVolumeView` attached off-screen to the key window, with its `UISlider` driven directly; the system HUD is suppressed by keeping that view in the hierarchy).
- `enum PlayerGestureEvent: Equatable { case tap, doubleTap, holdBegan, holdEnded, seekChanged(dx: Double), seekEnded(dx: Double), levelChanged(side: Side, dy: Double), levelEnded(side: Side); enum Side { case left, right } }`
- `final class PlayerGestureView: UIView`:
  - Recognisers: single tap (requires double tap to fail), double tap, a long press of 0.35 s, and a pan.
  - The pan uses `GestureMath.axis` to lock its direction.
  - When `allowsLevelGestures` is false, vertical pans are refused in `gestureRecognizerShouldBegin`, so the page scrolls.
  - When `ignoresEdges` is true, touches within `GestureMath.edgeInset` of the window edge are ignored.
- `enum FrameCapture { static func capture(from item: AVPlayerItem) -> UIImage?; static func saveToPhotos(_ image: UIImage) async -> Bool }`:
  - `capture` uses an `AVPlayerItemVideoOutput` the host view attaches when the item changes.
  - `saveToPhotos` uses `PHPhotoLibrary` with `.addOnly` authorization.

- [ ] **Step 1: Write the failing transition tests** in `PlayerTransitionTests` (host a `PlayerSurface` with an `AVPlayer` in a `UIWindow` on the test scene, as the old `FullScreenTests` did):

```swift
func testEnterAndLeaveLandscapeWithTheSurfaceOnScreen() async throws {
    // OrientationController.shared.enterLandscape(); wait up to 3 s for scene.interfaceOrientation.isLandscape
    // XCTAssertEqual(OrientationController.shared.presentation, .landscape); exitToInline(); wait for portrait
}
func testVerticalVideoIgnoresTurningAndLockHolds() {
    // videoIsVertical = true; deviceOrientationChanged(.landscapeLeft) → still .inline
    // horizontal: enterLandscape(); locked = true; deviceOrientationChanged(.portrait) → still .landscape
}
func testPictureInPictureControllerExistsAndStartsWhenSupported() async throws {
    // skip unless AVPictureInPictureController.isPictureInPictureSupported(); play the compile check's test media
    // from ProcessInfo MEDIA_DIR (skip if absent); startPiP(); wait for isPictureInPictureActive; stop it
}
func testVerticalPansAreRefusedInlineAndAcceptedInFullScreen() // gestureRecognizerShouldBegin with a synthetic vertical translation
```

- [ ] **Step 2: Implement** the files above.
- [ ] **Step 3: Push and watch the compile check.** Expected: the new tests pass (the PiP test may skip on CI and must report why); the old `FullScreenTests` still pass, since `VideoPlayerView` is untouched until Task 9.
- [ ] **Step 4: Commit and push.** `git commit -m "Player surface over AVPlayerLayer: PiP, orientation states, brightness/volume, gestures, frame capture"`

### Task 9: Video page model and the build A page

**Files:**
- Create: `ios/Sources/App/VideoPage/VideoRoute.swift`, `VideoPageModel.swift`, `PlaybackControlling.swift`, `VideoPageView.swift`, `ios/Tests/AppTests/VideoPageModelTests.swift`
- Modify: `ios/Sources/App/Playback/PlaybackController.swift`, `ios/Sources/App/Home/HomeView.swift` (push `VideoPageView`), `ios/Sources/App/Home/RecentStore.swift` (`PlayerRoute` maps to `VideoRoute`), `ios/Sources/App/AppSettings.swift`, `ios/Tests/AppTests/AppSettingsTests.swift`
- Delete: `ios/Sources/App/Player/PlayerScreen.swift`, `ios/Sources/App/Player/VideoPlayerView.swift`, `ios/Tests/AppTests/FullScreenTests.swift`

**Interfaces:**
- `struct VideoRoute: Hashable, Identifiable { bvid: String; cid: Int64?; startSeconds: Double?; id: UUID = UUID() }`
- `AppSettings` gains `autoplay: Bool` (key `player.autoplay`, default true), `loop: LoopMode` (`player.loop`, `.none`) and `fit: FitMode` (`player.fit`, `.fit`). Task 11's panels edit them.
- `PlaybackController` gains (all `@MainActor`):
  - `func start(at time: Double, autoplay: Bool) async` (the existing private `startPlayback`, made reachable; `start(at:)` stays and autoplays).
  - `private(set) var resume: (timeMs: Int64, cid: Int64)?`, filled from the first `PlayURLInfo` of a start.
  - Observed: `private(set) var position: Double` (updated every 0.25 s), `private(set) var duration: Double`, `private(set) var buffered: Double`, `private(set) var isPlaying: Bool`.
  - `var rate: Float` (applied as `player.defaultRate` and to `player.rate` while playing).
  - `func play()`, `func pause()`, `func seek(to seconds: Double) async`.
  - `var onEnd: (() -> Void)?` (fired on `AVPlayerItemDidPlayToEndTime` for the current item only).
  - `var videoSize: CGSize?` (from the chosen stream's width and height).
- `@MainActor protocol PlaybackControlling: AnyObject` covers exactly the members the page uses: `start(at:autoplay:)`, `resume`, `stop()`, `play()`, `pause()`, `seek(to:)`, `position`, `duration`, `buffered`, `isPlaying`, `rate`, `onEnd`, `phase`, `qualities`, `selectedQuality`, `playingQuality`, `codec`, `btrEnabled`, `mode`, `overlay`, `player`, `setQuality`, `setCodec`, `setBTR`, `videoSize`. `PlaybackController` conforms.
- `@MainActor @Observable final class VideoPageModel`:
  - `init(route: VideoRoute, client: BiliClient, settings: AppSettings, account: @escaping () -> Account, makeController: @escaping (PlayItem) -> PlaybackControlling)`.
  - Observed state: `detail: VideoDetail?`, `loadError: String?`, `current: PlayItem?`, `controller: PlaybackControlling?`, `related: [VideoCard]`, `chapters: [Chapter]`, `online: String?`, `ended: Bool`, `rate: Float` (1.0, kept across parts), `mirrored: Bool`, `sleepDeadline: Date?`.
  - `func load() async`:
    - Calls `videoDetail`, picks the cid (route cid, else `PlayerInfo.lastPlayCid` when it is one of the pages, else the first page), then calls `play(_:at:)`.
    - The start position is the route's, else `ResumePoint.start` with the controller's `resume`. When the route has no start, `play` first calls `start(at: 0, autoplay: false)`, then seeks to the resume point and plays.
    - Fetches `related` and `playerInfo` alongside, and starts the online poll (every 30 s while appeared).
  - `func play(_ item: PlayItem, at seconds: Double?) async`: stops the old controller after sending a heartbeat `mark`, makes a new one, keeps `rate`, and wires `onEnd`.
  - `func switchTo(_ item: PlayItem) async`: in place; reloads `detail` when the bvid changes.
  - `func handleEnd() async`:
    - Sends `HeartbeatSchedule.finished`, then applies `Autoplay.next` with `settings.autoplay`, `settings.loop`, the pages and the flattened season episodes.
    - `.replay` → seek 0 and play; `.play` → `switchTo`; `.stop` → `ended = true`.
  - `func appear()` / `func disappear()`: a covered page stops its controller, keeping the position; uncovering resumes paused.
  - `func backgrounded()` sends a heartbeat `mark`.
  - Heartbeats: `tick` on every position update; `mark` on pause, seek completion, part change and disappear. Nothing is sent when the account isn't logged in. Failures are logged at warn.
  - `func setSleepTimer(minutes: Int?)`: at the deadline, pause and clear.
- `VideoPageView(route:)`:
  - The player box (`PlayerSurface` + the M1 `StatsOverlay` when `settings.showOverlay`), 16:9 under a black status-bar area.
  - Under it, for build A only, a title line (`detail.title`) and a horizontal 分P chip strip when `pages.count > 1`. No other controls.
  - Loading spinner, and a failure message with 重试 inside the player box.
  - Chrome comes in Task 10; until then a tap toggles play/pause so the page is usable.
- Ruling: `Account` (existing enum in `AppEnvironment`) is passed as a closure, so tests can switch logged-in state.

- [ ] **Step 1: Write the failing tests** in `VideoPageModelTests`. Use a `FakePlayback: PlaybackControlling` and a `BiliClient` on a `FakeHTTP` app-test copy serving `DemoFixtures`:

```swift
func testLoadResumesAtTheSavedPositionForTheSamePart() async   // fixture resume 65 000 ms, cid matches → fake.startedAt == 0 then seek 65
func testRouteStartOverridesResume() async                      // route startSeconds 12 → start(at: 12), no extra seek
func testEndPlaysTheNextEpisodeInPlaceAndKeepsTheRate() async   // rate 2; handleEnd → detail reloaded for bvid B, new controller rate 2, route unchanged
func testEndOfTheLastEpisodeShowsTheEndScreen() async           // ended == true, controller not restarted
func testHeartbeatsOnlyWhenLoggedIn() async                     // logged out: no request to /x/click-interface/web/heartbeat after ticks past 15 s
func testCoveredPageStopsItsController() async                  // disappear → fake.stopped == true; appear → start(at: kept position) paused
func testSleepTimerPausesAtTheDeadline() async                  // minutes 0.001-equivalent via injected clock → pause called
```

- [ ] **Step 2: Implement** the model, the protocol, the controller additions and the page. Delete the three old files, and move the M1 `PlayerStatusBar` mode pill into `StatsOverlay`'s first line if it is still needed.
- [ ] **Step 3: Add demo screen `page`** (`-DemoScreen page` opens `VideoPageView` for the demo bvid; with `SIMCTL_CHILD_MEDIA_DIR` set, the demo controller plays a file from the test media through `AVPlayer` directly, otherwise the box stays black). Add `shoot 03-page 10 -DemoData YES -DemoScreen page` to the compile check, and run the screenshot step with `SIMCTL_CHILD_MEDIA_DIR=$RUNNER_TEMP/media`.
- [ ] **Step 4: Push and watch the compile check.** Expected: green; `03-page.png` shows the player box and the title line.
- [ ] **Step 5: Commit and push.** `git commit -m "Video page model: resume, autoplay in place, heartbeats, online count, sleep timer; AVKit player removed"`

### Task 10: Player chrome: portrait, landscape, 竖屏, progress bar, HUDs, end screens

**Files:**
- Create: `ios/Sources/App/Player/Chrome/ChromeState.swift`, `PortraitControls.swift`, `LandscapeChrome.swift`, `VerticalChrome.swift`, `ProgressBar.swift`, `TVThumb.swift`, `PlayerHUD.swift`, `EndScreens.swift`, `ios/Tests/AppTests/ChromeStateTests.swift`
- Modify: `ios/Sources/App/VideoPage/VideoPageView.swift`

**Interfaces:**
- `@MainActor @Observable final class ChromeState`:
  - `var visible: Bool`, `var hud: HUD?`, `var scrubbing: Double?`.
  - `func touch()` shows the controls and restarts a 3 s hide timer; the timer doesn't run while scrubbing or while a panel is open.
  - `func handle(_ event: PlayerGestureEvent, page: VideoPageModel, size: CGSize)` maps gestures:
    - tap → toggle; doubleTap → play/pause.
    - holdBegan → `rate = 2`, HUD `.speedUp`; holdEnded → restore.
    - seek events → `GestureMath.seekTarget` with HUD `.seek(label: TimeFormat.pair(target, duration))`, committed on `seekEnded`.
    - level events → `DeviceControls`, with HUD `.level(.brightness | .volume, value)`.
- `enum HUD: Equatable { case speedUp, seek(label: String), level(Level, Double); enum Level { case brightness, volume } }`
- `struct ProgressBar: View`:
  - Inputs: `position`, `duration`, `buffered`, `chapters: [Chapter]`, `onScrub: (Double) -> Void`, `onCommit: (Double) -> Void`.
  - Drawn as the played part in `Theme.pink`, buffered in white at 40%, the rest in white at 20%, with a chapter tick at each `from`.
  - The thumb is `TVThumb`: our own drawing of a small TV face, a rounded rect with two antennae and two eyes, about 22×18 pt.
  - While dragging, the current chapter's title shows above it.
- `PortraitControls` (15): back, ⋮, play/pause, `ProgressBar`, `TimeFormat.pair`, the 竖屏 button (corner brackets with a "竖屏" pill), and full screen. A thin 2 pt progress line shows while the controls are hidden.
- `LandscapeChrome` (04):
  - Top bar: back, title, "N人正在看", uploader avatar and name.
  - Its action icons and "+ 关注" sit behind `showsActions: Bool`. That flag is false in build A, and Task 21 turns it on.
  - Right edge: screenshot (`FrameCapture`, toast "已保存到相册" or "保存失败") and the rotation lock.
  - Bottom: time, bar, play, 弹 on/off, 弹 settings, the danmaku field, 倍速, quality short name, and 选集 when the video has parts or a 合集.
- `VerticalChrome` (09): back, "N人正在看", ⋮, the action column behind `showsActions`, uploader block, title, "N播放", bar, 发弹幕 field with 弹 toggle, 详情页, and full screen.
- `PlayerHUD` (25): "⏩ 倍速中" pill at the top centre; the seek label centred; the brightness/volume indicator centred with an icon and a bar.
- `EndScreens` (26, 27): portrait shows 推荐视频 with the first related card, 立即播放, 重播, 分享; landscape shows the uploader with avatar (关注 behind `showsActions`), 重播, actions behind `showsActions`, and a related row. 分享 always shows (the iOS share sheet with `https://www.bilibili.com/video/<bvid>`), since it needs no login.

- [ ] **Step 1: Write the failing tests** in `ChromeStateTests`:

```swift
func testControlsHideThreeSecondsAfterTheLastTouchButNotWhileScrubbing() async  // injected sleeper
func testHoldDoublesTheRateAndReleaseRestoresIt()                               // rate 1.25 → 2 → 1.25
func testHorizontalDragSeeksNinetySecondsPerWidthOnRelease() async             // width 400, dx 200, at 100 → seek(to: 145)
func testDoubleTapTogglesPlayback()
```

- [ ] **Step 2: Implement** the views. Sizes and paddings come from the screenshots. Landscape and 竖屏 chrome are laid out by `VideoPageView` from `OrientationController.presentation`: the page hides everything but the player, ignores safe areas, and hides the status bar and home indicator. Nothing is presented modally.
- [ ] **Step 3: Demo screens and shots.** Add `player-portrait` (controls visible, paused at 0:42), `player-landscape` (forced landscape, controls visible), `player-vertical`, `hud-speed`, `end-portrait` and `end-landscape`. Add `shoot` lines `04`–`09`.
- [ ] **Step 4: Push and watch the compile check.** Compare each shot with 15, 04, 09, 25, 26 and 27 and fix visible differences (layout, order, colours) before going on.
- [ ] **Step 5: Commit and push.** `git commit -m "Player chrome: portrait, landscape and 竖屏 controls, TV-thumb progress bar with chapters, HUDs, end screens"`

### Task 11: 清晰度, 倍速 and ⋮ panels

**Files:**
- Create: `ios/Sources/App/Player/Panels/SidePanel.swift`, `QualityPanel.swift`, `SpeedPanel.swift`, `MorePanel.swift`, `ios/Tests/AppTests/PanelPresentationTests.swift`
- Modify: `ios/Sources/App/AppSettings.swift`, `ios/Tests/AppTests/AppSettingsTests.swift`, `ios/Sources/App/VideoPage/VideoPageView.swift`

**Interfaces:**
- Uses `AppSettings.autoplay`, `.loop`, `.fit` (added in Task 9).
- `struct SidePanel<Content: View>: View`: in landscape a right-side panel, width 40% of the screen, on `Theme.panel`; in portrait a bottom sheet with the same content. Tapping outside dismisses it. It is an overlay inside the page, never a presented controller.
- `enum PlayerPanel: Identifiable { case quality, codec, speed, more, episodes, danmakuSettings }` (`danmakuSettings` is filled in by Task 13); `VideoPageView` holds `@State var panel: PlayerPanel?`.
- `EpisodesPanel` (the landscape 选集 button): the parts of a multi-part video, or else the current 合集 section's episodes, as rows with the playing one pink. Choosing a part calls `play`; choosing an episode calls `switchTo`.
- `QualityPanel` (05):
  - Rows: header 清晰度 with "高级设置 >" (opens `.codec`), then 自动, then `controller.qualities` best first.
  - Each row is a `Theme.panelCard` rounded card. Rows with `QualityRules.needsVip` get a pink 大会员 pill; the playing row is pink.
  - Tapping a VIP row without 大会员 toasts "开通大会员后可观看".
  - Choosing a row sets `settings.preferredQuality` and calls `setQuality`. Choosing 自动 uses `QualityRules.auto`.
- `CodecPanel` (in `QualityPanel.swift`): HEVC / AV1 / AVC rows, the current one pink. It sets `settings.preferredCodec` and calls `setCodec`.
- `SpeedPanel` (06): a right-aligned column of 3.0X, 2.0X, 1.5X, 1.25X, 1.0X, 0.75X, 0.5X on the dimmed video, the current one pink. It sets `page.rate`.
- `MorePanel` (20, 21):
  - Two square buttons: 稍后再看 (`addToWatchLater`; toast "已添加至稍后再看"; logged out → login) and 小窗播放 (`startPiP`).
  - 定时关闭 segmented row: 不开启, 15:00, 30:00, 60:00, 自定义. 自定义 opens a minutes wheel from 1 to 180.
  - A card with:
    - 自动连播 toggle.
    - 循环播放 segmented 单集循环 / 列表循环 / 不循环.
    - 镜像翻转 toggle (page only).
    - 画面尺寸 > (a sub-list of `FitMode`).
  - A card titled 测试 holding BTR 加速 (`setBTR`, and `settings.btrEnabled`) and 显示统计 (`settings.showOverlay`).

- [ ] **Step 1: Write the failing tests:**

```swift
// AppSettingsTests
func testPlayerSettingsDefaultsAndPersistence()   // (Task 9's settings, tested here) autoplay true, loop .none, fit .fit; set and reload from the same defaults
// PanelPresentationTests (host VideoPageView with demo data in a UIWindow; OrientationController.enterLandscape first)
func testEachPanelOpensAndClosesInLandscape() async throws   // for each PlayerPanel: set panel, wait 0.3 s, assert visible via accessibility identifier, tap outside, assert gone
func testEachPanelOpensAndClosesInPortrait() async throws
```

- [ ] **Step 2: Implement.** Give each panel the accessibility identifier `panel.<case>`.
- [ ] **Step 3: Shots.** `panel-quality`, `panel-speed` and `panel-more` (landscape). Compare them with 05, 06, 20 and 21.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Player panels: 清晰度 with codec, 倍速, ⋮ with sleep timer, autoplay, loop, mirror, fit, BTR and stats"`

### Task 12: Danmaku renderer and controller

**Files:**
- Create: `ios/Sources/App/Danmaku/DanmakuSettings.swift`, `DanmakuController.swift`, `DanmakuView.swift`, `ios/Tests/AppTests/DanmakuControllerTests.swift`
- Modify: `ios/Sources/App/AppSettings.swift`, `ios/Sources/App/VideoPage/VideoPageModel.swift`, `VideoPageView.swift`, `ios/Sources/App/DebugSupport/DemoFixtures.swift`

**Interfaces:**
- `struct DanmakuSettings: Codable, Equatable`:
  - Fields and defaults: `enabled = true`, `area = 0.5` (one of 0.1, 0.25, 0.5, 0.75, 1.0), `opacity = 1.0` (0.1...1), `scale = 1.0` (0.5...2.0), `speed = 2` (index into `scrollDurations = [11, 9, 7, 5.5, 4]`), `filter = DanmakuFilterOptions()`.
  - `static let defaults`.
  - Stored as JSON under the `AppSettings` key `danmaku.settings`, exposed as `AppSettings.danmaku: DanmakuSettings`.
- `@MainActor @Observable final class DanmakuController`:
  - `init(client: BiliClient, settings: AppSettings, ownHash: () -> String?)`.
  - `func load(cid: Int64, bvid: String, durationMs: Int64)` resets everything for a new part.
  - `func update(positionMs: Int64, playing: Bool)` is called on every display-link frame by the view. It fetches `DanmakuSegments.needed`, so each segment is requested once and a failed one is retried on the next boundary or seek, then filters through `DanmakuFilter` with the current rules and adds the result to the `DanmakuTimeline`.
  - `func seeked(toMs: Int64)`.
  - `private(set) var closed: Bool`.
  - `var rules: [BlockRule]`, set by Task 13's store; an empty list is acceptable until then.
  - `func showOwn(_ draft: DanmakuDraft)` inserts at the current time with `isOwn = true`.
  - `func pendingItems(atMs:) -> [DisplayDanmaku]` drains the timeline for the view.
- `final class DanmakuView: UIView`:
  - Driven by a `CADisplayLink`; reads the player's current time (`player.currentTime()`), not wall time, so pause, rate and seek follow the video.
  - Places each new item with `LaneLayout` (lane height = font line height × 1.2; lanes = `floor(bounds.height × area / laneHeight)`).
  - Draws each item as a cached text image: `UIGraphicsImageRenderer` of the text, white or its colour, with a 1 pt dark stroke. Own items get a 1 pt white rounded outline box.
  - Moves scrolling items each frame as `x = W - (t - start) × (W + w) / D`; reverse mode mirrors that.
  - Removes items when off screen or after 4 s (static).
  - Font point size is `(fontSize / 25) × scale × 17` inline and `× 22` in full screen; opacity comes from settings.
  - It is cleared and re-laid on seek, size change or settings change.
- The page creates one `DanmakuController` and hands the `DanmakuView` to `PlayerSurface(danmaku:)`. The 弹 toggles flip `settings.danmaku.enabled`.

- [ ] **Step 1: Write the failing tests** in `DanmakuControllerTests` (demo-fixture transport serving segment bytes built with a Debug-only encoder in `DemoFixtures`):

```swift
func testLoadsTheFirstSegmentAtStartAndTheNextNearTheBoundary() async  // update(0) → 1 request index 1; update(335_000) → index 2; repeated updates → no repeats
func testSeekFarAheadLoadsThatSegmentOnly() async                      // seeked(toMs: 800_000) → index 3
func testClosedSegmentStopsDanmaku() async                             // state 1 → closed == true, pendingItems empty
func testFailedSegmentRetriesOnTheNextSeek() async                     // first 500, then ok after seeked
func testOwnDanmakuAppearsAtOnce()                                     // showOwn → pendingItems(atMs: now) contains isOwn
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `danmaku-landscape` (demo segment with dense scroll, top and bottom items, paused mid-flight) and `danmaku-portrait`.
- [ ] **Step 4: Push and watch the compile check.** Check the shots for overlap (there must be none) and placement.
- [ ] **Step 5: Commit and push.** `git commit -m "Danmaku renderer: segments on demand, filters, lanes, video-time driven layers"`

### Task 13: 弹幕设置 panel and block words

**Files:**
- Create: `ios/Sources/App/Danmaku/DanmakuSettingsPanel.swift`, `BlockRuleStore.swift`, `BlockWordsView.swift`, `ios/Tests/AppTests/BlockRuleStoreTests.swift`
- Modify: `ios/Sources/App/Player/Panels/SidePanel.swift` (the `.danmakuSettings` case), `ios/Sources/App/AppEnvironment.swift` (one shared `BlockRuleStore`; `logout()` clears it)

**Interfaces:**
- `@MainActor @Observable final class BlockRuleStore`:
  - `init(client: BiliClient, now: @escaping () -> Date = Date.init)`; `private(set) var rules: [BlockRule]`.
  - `func refresh(force: Bool = false) async`: skipped within 600 s of the last success unless forced; empty when logged out.
  - `func add(_ kind: BlockRule.Kind, filter: String) async throws`: for `.user`, a typed uid is converted with `MidHash.of`.
  - `func delete(_ rule: BlockRule) async throws`; `func clear()`.
- `DanmakuSettingsPanel` (07, 08, 24):
  - Header 弹幕设置, with "查看更多 ⌄".
  - Card 1: 显示区域 (5 stops) and 不透明度. 查看更多 adds 字体大小 (50–200%, shown as a percentage) and 弹幕速度 (5 stops labelled 极慢, 较慢, 适中, 较快, 极快).
  - 画面防挡:
    - 按弹幕类型屏蔽: five square toggles, 固定 / 滚动 / 彩色 / 高级 / 计数, pink when blocked.
    - Toggles: 重复弹幕隐藏 (大量内容相同的弹幕会被隐藏) and 底部字幕区域防挡 (底部弹幕会被隐藏).
  - 更多工具: 弹幕观看屏蔽词 toggle (仅对我不展示特定弹幕) → `filter.applyRules`; 添加屏蔽词 > opens `BlockWordsView` (logged out → login).
  - Footer: ↻ 重置弹幕设置 → `DanmakuSettings.defaults`.
- `BlockWordsView`: in landscape a panel page inside `SidePanel`; in portrait a pushed page. It shows the rules grouped by 关键词 / 正则 / 用户, has an add field with a kind picker, and deletes on swipe.

- [ ] **Step 1: Write the failing tests:**

```swift
func testRefreshIsCachedForTenMinutes() async      // two refreshes 5 min apart → 1 request; 11 min → 2
func testLoggedOutGivesNoRulesAndNoRequest() async
func testAddingAUserConvertsTheUidToItsHash() async // add(.user, "12345") → form filter = MidHash.of(uid: 12345)
```

- [ ] **Step 2: Implement.** `VideoPageModel.load` calls `blockRules.refresh()`, and the danmaku controller reads `rules` from the store.
- [ ] **Step 3: Shots.** `panel-danmaku` (landscape, top), `panel-danmaku-more` (查看更多 expanded) and `block-words`. Compare with 07, 08 and 24.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "弹幕设置 panel and synced block words"`

### Task 14: Sending danmaku

**Files:**
- Create: `ios/Sources/App/Danmaku/DanmakuSendBar.swift`, `DanmakuStylePanel.swift`, `ios/Tests/AppTests/DanmakuSendTests.swift`
- Modify: `ios/Sources/App/Player/Chrome/LandscapeChrome.swift`, `VerticalChrome.swift`, `ios/Sources/App/VideoPage/VideoPageView.swift`

**Interfaces:**
- `struct DanmakuStyle: Equatable { var fontSize = 25; var mode = 1; var color: UInt32 = 0xFFFFFF; var gradient = false }` (kept for the page's life). `static let colors: [UInt32]` lists white, then the 11 colours in screenshot 23's order; sample their exact hex values from the image.
- `@MainActor @Observable final class DanmakuSendModel`:
  - `init(client: BiliClient, page: VideoPageModel, danmaku: DanmakuController, isVip: () -> Bool, isLoggedIn: () -> Bool)`.
  - `var text: String` (capped at 100 characters); `var style: DanmakuStyle`; `var sending: Bool`; `var needsLogin: Bool` (the page presents login when it turns true).
  - `func send() async -> String?`: returns the error message, or nil on success. Logged out → returns "需要登录" and sets `needsLogin = true`. Empty text is ignored. `danmaku.closed` → "UP主已关闭弹幕". On success it calls `danmaku.showOwn` and clears the text.
- `DanmakuSendBar` (22): a dark bar above the keyboard with the A button, a white rounded field with the placeholder "发个友善的弹幕见证当下", and a send arrow. Tapping the A button swaps the keyboard for `DanmakuStylePanel` (23). The 会员 chip is selectable only with `isVip`; otherwise tapping it toasts "开通大会员后可使用".
- Opening: the landscape field, 竖屏 发弹幕, and (in build B) 点我发弹幕. Playback keeps running.

- [ ] **Step 1: Write the failing tests:**

```swift
func testSendPostsTheDraftAndShowsItAtOnce() async     // form mode/fontsize/color from style, progress = page position ms; danmaku.showOwn called
func testLoggedOutAsksForLoginWithoutARequest() async
func testClosedVideoRefusesToSend() async
func testTextIsCappedAt100Characters()
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `danmaku-send` (keyboard area rendered by a demo placeholder, since the simulator keyboard may not show in screenshots) and `danmaku-style`. Compare with 22 and 23.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Send danmaku with size, position and colour"`

### Task 15: Ship build A

**Files:**
- Create: `docs/m2-phone-checklist.md` (section "Build A")
- Modify: `CLAUDE.md` (Status: build A done, phone test pending; How to test: mention `-DemoData`)

- [ ] **Step 1: Write the build A checklist.** Numbered steps KaiC can do on the phone:
  - Open a video from a pasted link and from recents.
  - Resume: a video watched halfway in the official app resumes there.
  - Each gesture in the small player and in full screen (brightness/volume only in full screen).
  - Turn the phone: landscape full screen and back. Rotation lock. The 竖屏 button. A vertical video ignores turning.
  - 清晰度 (incl. 高级设置 codec), 倍速, and every ⋮ row: sleep timer with 自定义 1 minute, 自动连播, 循环播放, 镜像翻转, 画面尺寸, BTR switch, stats.
  - Picture in picture by swiping home, and the 小窗播放 button.
  - Screenshot button saves to Photos.
  - Chapters on a video that has them.
  - End screens, with autoplay into the next 合集 episode.
  - Danmaku: showing, each 弹幕设置 control, adding and removing a block word in the app and seeing it in the official app, sending in each style.
  - History: 历史记录 in the official app shows the video at the right position.
  - BTR stats still show; compare first frame and 卡顿 with M1.
- [ ] **Step 2: Run the whole BiliCore suite and the Python tests on the PC**:
  - `swift test --package-path ios/Packages/BiliCore`
  - `python -m unittest discover -s tools -p "test_*.py"`

  Both must pass.
- [ ] **Step 3: Merge to main and ship** (Global Constraints): fast-forward `main` to `m2`, push, wait for the compile check on `main` to go green and look at every screenshot, then `python scripts/testflight.py start` and watch it in the background.
- [ ] **Step 4: Report to KaiC:** the build number, what is in it, and the checklist link. Go back to `m2` (`git checkout m2`) for build B.
- [ ] **Step 5: Commit and push** the checklist and the CLAUDE.md status on `m2`, then fast-forward `main` again.

---

# Build B: the page and the entry points

### Task 15b: Panel look, from KaiC's build A comparison

KaiC compared build A's panels with the official app (2026-10-17, ⋮ and 清晰度 in landscape). Design only, no new rows or buttons.

**Files:**
- Modify: `ios/Sources/App/Shared/Theme.swift`, `ios/Sources/App/Player/Panels/SidePanel.swift`, `QualityPanel.swift`, and any panel that sets its own card colour or background
- Test: the panel shots in the compile check

- [ ] **Step 1: Panel background fades into the video.** The official panel is a see-through dark layer that blends into the video on the side facing it, with no hard edge; ours is a flat, heavier black with a hard edge. Use a horizontal gradient (landscape; vertical for the portrait sheet) from clear at the video side to dark at the screen edge, lighter overall than today's `Theme.panel`.
- [ ] **Step 2: Softer cards.** Cards and the ⋮ square buttons are lighter and slightly see-through in the official app (about #2B2C30 with the video faintly behind), ours solid #212327. Change `Theme.panelCard` once so every panel (清晰度, 倍速, ⋮, 选集, 弹幕设置) follows.
- [ ] **Step 3: Selected quality row is bold.** The playing row's title is pink and semibold in the official app; ours is pink at regular weight.
- [ ] **Step 4: Official quality names.** Show the official app's own names instead of the server's description: `480P 标清` (seen in the official app; we showed `480P 清晰`). Keep a qn → name table in AppLogic with a test, fill the other rows from the official app when it shows them, and fall back to the server's text for a qn the table lacks.
- [ ] **Step 5: Shots.** Compare `11-panel-quality`, `11-panel-more` and `panel-danmaku` with KaiC's official screenshots side by side.

### Task 16: Actions API

**Files:**
- Create: `Sources/BiliAPI/ActionModels.swift`, `Sources/BiliAPI/BiliClient+Actions.swift`
- Test: `Tests/BiliAPITests/ActionsAPITests.swift`

**Interfaces (all `public`):**
- `struct VideoRelation { like, dislike, favorite, attention: Bool; coins: Int }`: GET `/x/web-interface/archive/relation` (`aid`, `bvid`).
- `struct UploaderCard { mid: Int64; name: String; face: String; fans: Int64; videos: Int64; isVip: Bool; following: Bool }`: GET `/x/web-interface/card` (`mid`, `photo=false`). `fans` = `data.follower`, `videos` = `data.archive_count`, `isVip` = `card.vip.status == 1`, `following` = `data.following`.
- `like(aid: Int64, bvid: String, on: Bool)`: POST `/x/web-interface/archive/like` `aid`, `like` (1 or 2).
- `struct TripleResult { like, coin, favorite: Bool; multiply: Int }`; `triple(aid:bvid:) -> TripleResult`: POST `/x/web-interface/archive/like/triple` with `aid`, `eab_x=2`, `ramval=0`, `source=web_normal`, `ga=1`, `spmid=333.788.0.0`, `statistics={"appId":100,"platform":5}`.
- `coin(aid:bvid:multiply:alsoLike:)`: POST `/x/web-interface/coin/add` `aid`, `multiply`, `select_like` (0/1).
- `coinBalance() -> Double`: GET `https://account.bilibili.com/site/getCoin` → `data.money`.
- `struct FavFolder { id: Int64; title: String; count: Int; isPrivate: Bool; contains: Bool; isDefault: Bool }`.
  - `favouriteFolders(mid:aid:) -> [FavFolder]`: GET `/x/v3/fav/folder/created/list-all` `up_mid`, `rid`, `type=2`. `isPrivate` = `attr & 1 == 1`; `isDefault` = `attr & 2 == 0`; `contains` = `fav_state == 1`.
- `updateFavourites(aid:add:remove:)`: POST `/x/v3/fav/resource/batch-deal` `rid`, `type=2`, `add_media_ids`, `del_media_ids` (comma lists, may be empty).
- `createFolder(title:isPrivate:) -> FavFolder`: POST `/x/v3/fav/folder/add` `title`, `privacy` (0/1).
- `countShare(aid:)`: POST `/x/web-interface/share/add` `aid`.
- `follow(mid:on:)`: POST `/x/relation/modify` `fid`, `act` (1/2), `re_src=14`; referer `https://space.bilibili.com/<mid>`.
- `struct VideoTag { id: Int64; name: String; kind: Kind; enum Kind { case normal, topic, bgm } }`; `tags(bvid:cid:)`: GET `/x/web-interface/view/detail/tag`.
- Every POST uses referer `https://www.bilibili.com/video/<bvid>` where a bvid is known.

- [ ] **Step 1: Write the failing tests**, one per call. Each asserts the exact form body (sorted, with `csrf`) or the query, plus the decoded result. Add `testFavouriteFolderFlags` (attr 0, 1, 2, 3) and `testCoinErrorKeepsServerMessage` (code 34005 "超过投币上限啦~" → `.api(34005, "超过投币上限啦~")`).
- [ ] **Step 2: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter ActionsAPITests`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole package**, all pass.
- [ ] **Step 5: Commit and push.** `git commit -m "BiliAPI: relation, uploader card, like, 三连, coin, favourites, share, follow, tags"`

### Task 17: Comments API and rich text

**Files:**
- Create: `Sources/BiliAPI/CommentModels.swift`, `Sources/BiliAPI/BiliClient+Comments.swift`, `Sources/BiliAPI/RichText.swift`
- Test: `Tests/BiliAPITests/CommentsAPITests.swift`, `Tests/BiliAPITests/RichTextTests.swift`

**Interfaces (all `public`):**
- `enum RichRun: Equatable, Sendable { case text(String), emote(token: String, url: String, size: Int), mention(name: String, mid: Int64), link(title: String, url: String), video(id: String), timestamp(label: String, seconds: Int) }`
- `struct EmoteRef { url: String; size: Int }`; `struct LinkRef { title: String; url: String }`
- `enum RichText { static func runs(_ message: String, emotes: [String: EmoteRef], mentions: [String: Int64], links: [String: LinkRef]) -> [RichRun] }`:
  - Tokens are found in this order: emote keys (`[doge]`), `@name` for names in `mentions`, link keys (each replaced once), `BV[0-9A-Za-z]{10}` and `av\d+`, then `\d{1,2}[:：]\d{2}(?:[:：]\d{2})?` timestamps.
  - A `[token]` missing from `emotes` stays text.
  - Adjacent text runs are merged.
  - Splitting works on `Character` boundaries.
- `struct CommentMember { mid: Int64; name: String; face: String; level: Int; isVip: Bool; pendant: String?; fanCardImage: String?; fanCardNumber: String? }`
- `struct CommentPicture { url: String; width: Double; height: Double }`
- `struct Comment: Identifiable { rpid, oid, mid, root, parent: Int64; ctime: Int64; likes: Int64; replyCount: Int; action: Int; member: CommentMember; message: String; runs: [RichRun]; pictures: [CommentPicture]; location: String?; upLiked: Bool; isPinned: Bool; previewReplies: [Comment]; id: Int64 { rpid } }`
  - `location` drops the "IP属地：" prefix; `upLiked` = `up_action.like`.
  - Member fields: `level_info.current_level`, `vip.vipStatus == 1`, `pendant.image` (empty → nil), `user_sailing.cardbg.image` and `.fan.num_desc`.
  - Content fields: `content.emote` (key → `url`, `meta.size`), `content.at_name_to_mid`, `content.jump_url` (key → `title`; url = `pc_url` or the key), `content.pictures` (`img_src`, `img_width`, `img_height`).
  - Confirm these names against one live response saved under `local/` (never committed) before writing the fixture.
- `enum CommentSort: Int { case hot = 3, time = 2 }`
- `struct CommentPage { comments: [Comment]; pinned: Comment?; nextOffset: String?; isEnd: Bool; total: Int }`
- `comments(aid:sort:offset:) -> CommentPage`:
  - GET `/x/v2/reply/wbi/main` signed with `oid`, `type=1`, `mode`, and `pagination_str` = `{"offset":"<offset>"}` (`""` on page one). `seek_rpid` is absent.
  - On `-352`, `-403` or HTTP 412 it retries once on `/x/v2/reply/main` unsigned.
  - `pinned` comes from `data.top_replies[0]` (marked `isPinned`) and is only kept on page one.
  - `total` = `data.cursor.all_count`.
  - Codes 12002 and 12061 (comments closed) throw `.api` with the server message, which the UI shows in place of the list.
- `struct ThreadPage { root: Comment; replies: [Comment]; total: Int; isEnd: Bool }`
  - `thread(aid:root:page:sort:)`: GET `/x/v2/reply/reply` `oid`, `type=1`, `root`, `pn`, `ps=20`, `sort` (0 time, 1 hot).
- `postComment(aid:message:root:parent:syncToDynamic:) -> Comment`: POST `/x/v2/reply/add` `oid`, `type=1`, `message`, plus `root` and `parent` only when non-zero, and `sync_to_dynamic=1` only when set. Returns `data.reply`.
- Comment actions: `likeComment(aid:rpid:on:)` POST `/x/v2/reply/action`; `hateComment(aid:rpid:on:)` POST `/x/v2/reply/hate`; `deleteComment(aid:rpid:)` POST `/x/v2/reply/del` (form `oid`, `type=1`, `rpid`, and `action` 1/0 for the first two).
- Emotes:
  - `struct Emote { token: String; url: String; large: Bool }`; `struct EmotePackage { id: Int64; name: String; icon: String; isText: Bool; emotes: [Emote] }`.
  - `emotePackages()`: GET `/x/emote/user/panel/web` `business=reply`. `isText` = `type == 4`; `large` = `meta.size != 1`.

- [ ] **Step 1: Write the failing tests:**

```swift
func testRunsSplitEmotesMentionsLinksVideosAndTimestamps() {
    let runs = RichText.runs("看[doge]@小明 BV1GJ411x7h7 在03:15这里", emotes: ["[doge]": .init(url: "u", size: 1)],
                             mentions: ["小明": 42], links: [:])
    XCTAssertEqual(runs, [.text("看"), .emote(token: "[doge]", url: "u", size: 1), .mention(name: "小明", mid: 42), .text(" "),
                          .video(id: "BV1GJ411x7h7"), .text(" 在"), .timestamp(label: "03:15", seconds: 195), .text("这里")])
}
func testRunsKeepEmojiAndUnknownTokens() {
    XCTAssertEqual(RichText.runs("😀[未知]😀[doge][doge]", emotes: ["[doge]": .init(url: "u", size: 1)], mentions: [:], links: [:]),
                   [.text("😀[未知]😀"), .emote(token: "[doge]", url: "u", size: 1), .emote(token: "[doge]", url: "u", size: 1)])
}
func testCommentPageDecodesMembersPicturesPinnedAndCursor() async throws
func testCommentsFallBackToTheUnsignedRouteOnRiskControl() async throws
func testClosedCommentsThrowTheServerMessage() async
func testPostCommentReplyFields() async throws   // root 10 parent 11 → body has both; top-level → neither
func testThreadQuery() async throws              // pn 2, ps 20, sort 0
func testEmotePackagesFlagTextPackages() async throws
```

- [ ] **Step 2: Run to see them fail.** `swift test --package-path ios/Packages/BiliCore --filter "CommentsAPITests|RichTextTests"`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the whole package**, all pass.
- [ ] **Step 5: Commit and push.** `git commit -m "BiliAPI: comments, threads, posting, emotes, rich-text runs"`

### Task 18: Feed and history API, history grouping

**Files:**
- Create: `Sources/BiliAPI/FeedModels.swift`, `Sources/BiliAPI/BiliClient+Feed.swift`, `Sources/AppLogic/HistoryGrouping.swift`
- Test: `Tests/BiliAPITests/FeedAPITests.swift`, `Tests/AppLogicTests/HistoryGroupingTests.swift`

**Interfaces (all `public`):**
- `struct FeedCard: Identifiable { aid: Int64; bvid: String; cid: Int64; title: String; cover: String; duration: Int; views: Int64; danmaku: Int64; ownerName: String; ownerMid: Int64; reason: String?; isVertical: Bool; id: String { bvid } }` (`reason` = `rcmd_reason.content`, e.g. "2万点赞"; `isVertical` from `dimension`).
- `recommendFeed(index: Int) -> [FeedCard]`: GET `/x/web-interface/wbi/index/top/feed/rcmd` signed with `fresh_type=4`, `ps=12`, `fresh_idx=<index>`, `fresh_idx_1h=<index>`, `brush=<index>`, `feed_version=V8`. Only items with `goto == "av"` are kept.
- `struct HistoryItem: Identifiable { bvid: String; cid: Int64; title: String; cover: String; ownerName: String; progress: Int; duration: Int; viewAt: Int64; device: Int; part: String?; id: String }`
  - `progress` -1 means watched to the end.
  - `device` comes from `history.dt`; 1, 3, 5 and 7 are phone, 2 and 33 are PC, everything else pad/TV. The row icon follows it.
- `struct HistoryCursor { max: Int64; viewAt: Int64 }`; `struct HistoryPage { items: [HistoryItem]; next: HistoryCursor? }`
  - `history(after: HistoryCursor?) -> HistoryPage`: GET `/x/web-interface/history/cursor` `max`, `view_at`, `business=archive`, `ps=20`. `next` is nil when the page is empty.
- `enum HistoryGrouping { static func sections(_ items: [HistoryItem], now: Date, timeZone: TimeZone = .current) -> [(title: String, items: [HistoryItem])] }`: titles 今天, 昨天, `M月d日` (same year) and `yyyy年M月d日`.

- [ ] **Step 1: Write the failing tests:** `testFeedKeepsOnlyVideosAndReadsReasonAndShape`, `testFeedQuery`, `testHistoryPagesWithTheCursor`, `testHistoryEmptyPageEndsPaging`, `testGroupingTitles` (UTC+8, now = 2026-10-17 01:00: items at 00:30 → 今天, 2026-10-16 23:00 → 昨天, 2026-10-01 → 10月1日, 2025-12-31 → 2025年12月31日).
- [ ] **Step 2: Run to see them fail**, implement, run the whole package.
- [ ] **Step 3: Commit and push.** `git commit -m "BiliAPI: 推荐 feed and history; history day groups"`

### Task 19: App keys from the build, APP signing, TV login, dislike

**Files:**
- Create: `tools/write_app_keys.py`, `tools/test_write_app_keys.py`, `Sources/BiliAPI/AppSigner.swift`, `Sources/BiliAPI/BiliClient+App.swift`, `Tests/BiliAPITests/AppSignerTests.swift`, `ios/Sources/App/Account/AppTokenStore.swift`
- Modify: `.github/workflows/ios-compile.yml`, `.github/workflows/testflight.yml` (an "App keys" step before project generation, with `env: BILI_APP_KEYS: ${{ secrets.BILI_APP_KEYS }}` and `run: python3 tools/write_app_keys.py ios/Generated/AppKeys.swift`), `ios/project.yml` (sources add `- path: Generated/AppKeys.swift`), `ios/Sources/App/AppEnvironment.swift` (`logout()` clears the token)

**Interfaces:**
- `tools/write_app_keys.py`: `main(out_path, env=os.environ) -> int`.
  - It reads `BILI_APP_KEYS` as `"<appkey>:<appsec>"`, prints `::add-mask::` for each half, and writes `enum AppKeys { static let tv: (key: String, secret: String)? = ("…", "…") }`.
  - Without the variable, or with a malformed value, it writes `= nil` and prints a notice. It exits 0 in both cases, so forks and the PC still build.
  - Values are escaped for a Swift string literal.
- `struct AppSigner: Sendable { init(appKey: String, appSecret: String); func signed(_ params: [String: String], ts: Int) -> [String: String] }`:
  - Adds `appkey` and `ts`.
  - Builds the query with keys sorted and values percent-encoded as in `FormEncoding`.
  - `sign` = MD5 hex of that query plus the secret.
- `BiliClient` (passport and app hosts):
  - `tvAuthCode(signer:) -> (url: String, authCode: String)`: POST `https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code`, signed form `local_id=0`, no csrf.
  - `enum TVLoginState { case waiting, expired, confirmed(accessToken: String, mid: Int64) }`
  - `tvPoll(signer:authCode:) -> TVLoginState`: POST `.../qrcode/poll`, signed `auth_code`, `local_id=0`. Code 0 → confirmed; 86039 and 86090 → waiting; 86038 → expired; anything else throws.
  - `dislike(aid:on:accessToken:signer:)`: POST `https://app.bilibili.com/x/v2/view/dislike`, signed form `aid`, `dislike` (0 to dislike, 1 to undo), `access_key`. A non-JSON or `code != 0` reply throws.
  - These three calls must not add `csrf` and must not send cookies to `app.bilibili.com`. Add a `cookies: Bool` parameter (default true) to the shared request path, and pass `false` here.
- `enum AppTokenStore { static func load() -> String?; static func save(_ token: String) -> Bool; static func delete() }`: Keychain service `com.kaichuan.bilinative.apptoken`.

- [ ] **Step 1: Write the failing tests.**

  Python (`tools/test_write_app_keys.py`):
  - `test_writes_masked_keys`: env `{"BILI_APP_KEYS": "k1:s1"}` → the file contains `("k1", "s1")` and stdout has two `::add-mask::` lines.
  - `test_missing_secret_writes_nil`.
  - `test_escapes_quotes`.

  Swift:

```swift
func testSignerMatchesTheDocumentedAlgorithm() {
    let signed = AppSigner(appKey: "testkey", appSecret: "testsecret").signed(["b": "你好", "a": "1"], ts: 100)
    XCTAssertEqual(signed["sign"], "a650ecac0ce853a58e81f3366d428dbb")   // md5("a=1&appkey=testkey&b=%E4%BD%A0%E5%A5%BD&ts=100" + "testsecret")
    XCTAssertEqual(signed["appkey"], "testkey"); XCTAssertEqual(signed["ts"], "100")
}
func testTVPollStates() async throws          // 86039 → waiting, 86038 → expired, 0 → confirmed with token and mid
func testDislikeSendsNoCookiesAndNoCSRF() async throws
```

- [ ] **Step 2: Run to see them fail**, implement, run `swift test` and the Python tests.
- [ ] **Step 3: Tell KaiC the manual step**, in the task report and in `docs/m2-phone-checklist.md` "Before build B":
  1. Open the bilibili-API-collect page `docs/misc/sign/APPKey.md` (GitHub: SocialSisterYi/bilibili-API-collect), find the row whose platform is the TV client (云视听小电视, appkey starting `4409e2ce`), and copy its appkey and appsec.
  2. In a terminal in the repo run `gh secret set BILI_APP_KEYS -R KaiC5504/BiliNative` and paste `appkey:appsec` (one line, colon between) when asked.
  3. Check with `gh secret list -R KaiC5504/BiliNative` that `BILI_APP_KEYS` is listed.
- [ ] **Step 4: Push and watch the compile check.** It must be green with or without the secret. The "App keys" step prints either "app keys written" or the notice, never the values.
- [ ] **Step 5: Commit and push.** `git commit -m "App keys from a GitHub secret, APP signing, TV-login token, dislike call"`

### Task 20: 简介 tab and the page layout

**Files:**
- Create: `ios/Sources/App/VideoPage/PageTabs.swift`, `IntroTab.swift`, `UploaderRow.swift`, `TitleBlock.swift`, `CollectionSheet.swift`, `PartList.swift`, `RelatedList.swift`, `CollapsingPlayer.swift`, `ios/Tests/AppTests/IntroTabTests.swift`
- Modify: `ios/Sources/App/VideoPage/VideoPageView.swift` (the build A title line goes), `VideoPageModel.swift` (adds `uploader: UploaderCard?`, `tags: [VideoTag]`, `relation: VideoRelation?`, loaded with the detail when logged in)

**Interfaces:**
- `PageTabs` (03, 10): 简介 / 评论 N tabs with a pink underline. At the right, the "点我发弹幕" field joined to the 弹 toggle (`BorrowedIcon.danmakuOn/Off`); it opens Task 14's send bar. The tabs switch by tap or by swiping sideways (a paged `TabView`).
- `IntroTab`:
  - `UploaderRow`: avatar, name (pink for VIP), "N粉丝 N视频" via `CountFormat`, and the 关注 pill. `staff` videos show an avatar row instead. The follow action is a closure that Task 21 wires.
  - `TitleBlock`: 活动 tag when `detail.honor` is set, the bold title, and ⌄/⌃. The meta line shows plays, danmaku, `TimeFormat.publish` and "N人正在看".
  - Expanded (18): the BV id; "⊘ 未经作者授权禁止转载" when `copyright == 1`; the description as `RichText` runs from `descParts`, where a timestamp seeks the player and a mention is blue but inert; and tag chips that are not tappable.
  - The action row slot (Task 21).
  - The 合集 row "合集 · 名称" with "N/M >". It opens `CollectionSheet` (19): title, intro with 展开, 选集 with 正序/倒序, rows of the current section with the playing one pink, and 内容到底啦. Choosing an episode calls `switchTo`.
  - Multi-part videos show a part chip strip with "选集 N/M >" opening `PartList`.
  - `RelatedList`: rows as in 03 and 18. A tap pushes a new `VideoPageView` (`VideoRoute(bvid:cid:nil)`).
- `CollapsingPlayer` (11, 12): while paused, scrolling the tab content shrinks the player box from 16:9 down to a 56 pt bar with back, "▶ 继续播放" and ⋮. Tapping 继续播放 scrolls to the top and plays. While playing the player never shrinks.

- [ ] **Step 1: Write the failing tests** in `IntroTabTests` (model-level):

```swift
func testCollectionPositionFindsTheEpisodeByCid()      // "2/3" for the demo season's second episode
func testDescriptionTimestampSeeksThePlayer() async    // tapping run .timestamp(195) → controller.seek(to: 195)
func testRelatedTapPushesANewRoute()                  // navigation path gains VideoRoute(bvid: related[0].bvid)
```

  Also a `CollapsingPlayer` geometry test: `height(forOffset:paused:)` returns full height while playing, and 56 when paused past the threshold.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `page-intro` (03 layout with demo data), `page-intro-expanded` (18), `sheet-collection` (19), `page-collapsed` (12). Compare and fix.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Video page: tabs, 简介 with uploader, title, 合集 and 分P, related, collapsing player"`

### Task 21: Actions on the page and in full screen

**Files:**
- Create: `ios/Sources/App/VideoPage/ActionsModel.swift`, `ActionRow.swift`, `TripleRing.swift`, `LoginGate.swift`, `ios/Tests/AppTests/ActionsModelTests.swift`
- Modify: `IntroTab.swift`, `UploaderRow.swift`, `Player/Chrome/LandscapeChrome.swift`, `VerticalChrome.swift`, `EndScreens.swift` (`showsActions` becomes true), `VideoPageView.swift`

**Interfaces:**
- `@MainActor @Observable final class ActionsModel`:
  - `init(client: BiliClient, detail: VideoDetail, relation: VideoRelation?, uploader: UploaderCard?, isLoggedIn: @escaping () -> Bool, requestLogin: @escaping () -> Void, toast: @escaping (String) -> Void)`.
  - Observed: `liked`, `disliked`, `favorited`, `following: Bool`; `coins: Int`; `likeCount`, `coinCount`, `favCount`, `shareCount: Int64`.
  - `func toggleLike() async`, `func triple() async`, `func coin(_ multiply: Int, alsoLike: Bool) async`, `func applyFavourites(add: [Int64], remove: [Int64]) async`, `func toggleFollow() async` (unfollow is confirmed by the view first), `func shared() async` (counts the share after the share sheet completes). `toggleDislike()` is added in Task 23; until then the 不喜欢 button shows and does nothing.
  - Every action, in order:
    1. Logged out → `requestLogin()` and return.
    2. Apply the change optimistically.
    3. Call the API.
    4. On error, roll back and toast `BiliError.userMessage`. A `needsLogin` error also calls `requestLogin()`.
  - Like clears dislike, and dislike clears like.
  - `triple` with all three already done toasts "已三连" and sends nothing. On success it sets each flag from the `TripleResult`, adds +1 to like and favourite where newly set, and adds `multiply` coins.
  - `var maxCoins: Int`: `detail.copyright == 2 ? 1 : 2`, minus `coins`.
  - `func canGive(_ multiply: Int, balance: Double) -> Bool`.
- `LoginGate`: a view modifier that presents the existing `LoginView` as a sheet when `requestLogin` fires.
- `ActionRow` (03): 点赞, 不喜欢, 投币, 收藏, 分享. Icons are SF Symbols, filled and pink when active, with counts via `CountFormat`; 不喜欢 shows its label instead of a count.
  - A hold of 0.2 s on 点赞 starts `TripleRing`: rings fill over 1.2 s around 点赞, 投币 and 收藏. Releasing early cancels; completing calls `triple()` with a pink burst.
  - 投币 opens the coin dialog and 收藏 the favourites sheet (Task 22). 分享 opens the iOS share sheet.
- Full screen: `LandscapeChrome`, `VerticalChrome` and `EndScreens` show their action icons and 关注 using the same `ActionsModel`.

- [ ] **Step 1: Write the failing tests** in `ActionsModelTests` (`FakeHTTP` with demo fixtures):

```swift
func testLikeIsOptimisticAndClearsDislike() async
func testFailureRollsBackAndToastsTheServerMessage() async
func testExpiredLoginRollsBackAndAsksForLogin() async      // server -101 → liked false again, requestLogin called once
func testLoggedOutSendsNothingAndAsksForLogin() async
func testTripleSetsAllThreeAndCounts() async
func testTripleWhenAllDoneOnlyToasts() async               // "已三连", no request
func testCoinLimits() {                                    // repost → maxCoins 1; one given → 1; balance 1.5 → canGive(2) false
}
func testUnfollowAndFollowRequests() async                 // act 2 then 1
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `page-actions-active` (liked, coined and favourited states) and `player-landscape-actions` (04 with actions). Compare with 03 and 04.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Actions: like, 三连, coin, favourite, share, follow with optimistic state and login gating"`

### Task 22: Coin dialog and favourites sheet

**Files:**
- Create: `ios/Sources/App/VideoPage/CoinDialog.swift`, `FavouriteSheet.swift`, `ios/Tests/AppTests/ActionPresentationTests.swift`
- Modify: `ActionRow.swift`, `LandscapeChrome.swift`, `VerticalChrome.swift`, `EndScreens.swift`

**Interfaces:**
- `CoinDialog(actions: ActionsModel, balance: Double?)` (15):
  - A dimmed overlay inside the page, not a presented controller.
  - Two crate cards built from `BorrowedIcon.art("ic_pay_coins_box")` with `ic_coins_one`/`ic_coins_two`, labelled "1 硬币" and "2 硬币". The selected card is larger. ◀ ▶ (`ic_left`/`ic_right`, `_disable` when unavailable) and a sideways swipe change the selection.
  - The mascot `ic_22_gun_sister` (22娘 in school uniform, as in 15) runs in from below. Swiping up on the dialog, or tapping the mascot, throws: the coin flies up while `ic_thunder_1`–`3` play as a short lightning burst on the crate, then `coin(_:alsoLike:)` runs. `ic_22_mario` is unused.
  - With `balance < 1` the dialog shows `ic_22_not_enough_pay` and "硬币不足".
  - Text: "上滑或点击22娘投硬币", "硬币余额：N" (one decimal).
  - Bottom: "☑ 同时点赞内容" (remembered in `AppSettings`, key `coin.alsoLike`, default true), a round ✕ (`ic_panel_close`), and "如何获取硬币？", which opens `https://www.bilibili.com/blackboard/help.html` in Safari.
  - When the borrowed art is missing, the same layout uses plain shapes: brown rounded squares and the SF Symbol `bitcoinsign.circle`. No mascot.
  - In landscape it is the same dialog, centred, scaled to the height.
  - The balance comes from `coinBalance()` when the dialog opens.
- `FavouriteSheet(actions: ActionsModel)`:
  - A bottom sheet in portrait, and the `SidePanel` in landscape.
  - Title 选择收藏夹. Rows are folders with a check when `contains`, plus a lock for private ones and the count.
  - "+ 新建收藏夹" opens an inline name field and a 私密 switch, calling `createFolder`.
  - 完成 calls `applyFavourites` with the difference from the starting state.
- The unfollow confirm is an alert ("确定不再关注？", 取消 / 确定). It is the one system alert here, and it gets a presentation test in landscape.

- [ ] **Step 1: Write the failing tests** in `ActionPresentationTests` (page hosted in a window with demo data):

```swift
func testCoinDialogOpensAndClosesInPortraitAndLandscape() async throws
func testFavouriteSheetOpensAndAppliesTheDifference() async throws     // tick one more folder, untick one → batch-deal add=…&del=…
func testUnfollowAlertInLandscape() async throws
func testShareSheetPresentsOverTheRotatedPlayer() async throws         // UIActivityViewController presented from the key window's top controller, then dismissed
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `coin-dialog` (with the borrowed art) and `favourite-sheet`. Compare `coin-dialog` with 15.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Coin dialog with the borrowed art, favourites sheet, unfollow confirm"`

### Task 23: App token sheet and 不喜欢

**Files:**
- Create: `ios/Sources/App/Account/TVLoginSheet.swift`, `ios/Tests/AppTests/TVLoginModelTests.swift`
- Modify: `ActionsModel.swift`, `ActionRow.swift`

**Interfaces:**
- `@MainActor @Observable final class TVLoginModel`:
  - `init(client: BiliClient, signer: AppSigner?, sleep: @escaping (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) })`.
  - `enum State { case unavailable, starting, confirming(url: URL), expired, done, failed(String) }`.
  - `func start() async`: no signer → `.unavailable`. Otherwise it calls `tvAuthCode`, moves to `.confirming`, and polls every 2 s. `confirmed` → `AppTokenStore.save` and `.done`; `expired` → `.expired`.
  - `func cancel()`.
- `TVLoginSheet`:
  - It explains in one line: "不喜欢需要哔哩哔哩确认一次授权" and "在下方页面点「确认登录」".
  - It shows the confirm URL in a `WKWebView` using `WKWebsiteDataStore.default()`, which holds the login cookies from M1's login.
  - States: 已过期 with 重试, and 完成, which closes the sheet.
  - It gets a presentation test.
- `ActionsModel.toggleDislike()`:
  - Without `AppKeys.tv`, the button is greyed and the tap toasts "此版本不支持不喜欢".
  - Without a stored token, it opens the sheet.
  - Otherwise it calls `dislike`. If the server reports an invalid token (codes -101 or -2), it deletes the token and opens the sheet again.
  - Ruling: the dislike call is signed with the TV pair that issued the token (spec 11 leaves this to the builder). If the phone test shows it refused, try the same call without `appkey`/`sign` and only `access_key` before giving up, and record the result in `docs/background.md`.

- [ ] **Step 1: Write the failing tests:**

```swift
func testNoKeysMeansUnavailable() async
func testPollsUntilConfirmedAndStoresTheToken() async   // waiting, waiting, confirmed → done; AppTokenStore.load() == token (delete after)
func testExpiredCodeEndsInExpired() async
func testTVLoginSheetPresentsAndDismisses() async throws
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Push and watch the compile check.**
- [ ] **Step 4: Commit and push.** `git commit -m "不喜欢 through a one-time TV-login confirmation"`

### Task 24: Comments tab and threads

**Files:**
- Create: `ios/Sources/App/Comments/CommentsModel.swift`, `CommentsTab.swift`, `CommentRow.swift`, `RichTextView.swift`, `ThreadView.swift`, `PictureViewer.swift`, `ios/Tests/AppTests/CommentsModelTests.swift`
- Modify: `ios/Sources/App/VideoPage/PageTabs.swift`, `VideoPageView.swift`

**Interfaces:**
- `@MainActor @Observable final class CommentsModel`:
  - `init(client: BiliClient, aid: Int64, upMid: Int64, isLoggedIn: @escaping () -> Bool, requestLogin: @escaping () -> Void)`.
  - Observed: `sort: CommentSort` (`.hot`), `comments: [Comment]`, `pinned: Comment?`, `total: Int`, `isEnd: Bool`, `closedMessage: String?`, `loading: Bool`, `error: String?`.
  - `func loadMore() async`: passes the last `nextOffset`; does nothing when `isEnd` or already loading.
  - `func setSort(_:) async`: resets and reloads.
  - `func toggleLike(_ c: Comment) async`, `func toggleHate(_ c: Comment) async`, `func delete(_ c: Comment) async`, `func inserted(_ c: Comment)` (posted comments go to the top).
  - Thread state: `thread: ThreadState?` with `root`, `replies`, `sort` (`.time` by default), `page`, `isEnd`, plus `func openThread(_ root: Comment) async`, `func closeThread()` and `func loadMoreThread() async`.
- `CommentRow` (10):
  - Avatar with its pendant image and a pink 大 badge for VIP.
  - Name (pink for VIP), the LV badge (our drawn `LV1`–`LV6` capsule in the level colours from the screenshot), and an UP badge when `mid == upMid`.
  - The fan card at the right when present (image plus "NO. 017949").
  - `RichTextView`, then pictures (a 3-column grid; one picture shown large). Tapping a picture opens `PictureViewer` (full screen with swiping between pictures; an overlay, not a presented controller).
  - Meta line: `TimeFormat.relative` and the location, 回复, 👍 count, 👎, and ⋮ (复制, plus 删除 for your own, with a confirm).
  - Under it, a preview box with up to two replies and "共N条回复 >", and "UP主觉得很赞" when `upLiked`.
- `RichTextView`: runs into one `Text` with inline emote images (via `Text(Image)` from cached `UIImage`s, sized `20 × size` pt), mentions and links in `Theme.link`, and tappable timestamps (seek) and video ids (push a page). Taps go through `AttributedString` links with a custom URL scheme `bilinative://`, handled by an `OpenURLAction`.
- `CommentsTab`: header 热门评论/最新评论 with the "☰ 按热度/按时间" switch, the pinned comment with a 置顶 label, the list with endless scroll, "没有更多了", `closedMessage` in place of the list, and a retry row on error. The fixed bottom bar "哎呦，不错哦，发条评论吧" and emote button open Task 25's composer.
- `ThreadView` (13): replaces the tab content with header 评论详情 and ✕, the root comment, a grey band, "相关回复共N条" with 按时间/按热度, and the replies.
- The 评论 icon in the landscape and 竖屏 chrome calls `OrientationController.exitToInline()` and selects the 评论 tab.

- [ ] **Step 1: Write the failing tests:**

```swift
func testPagingPassesTheOffsetAndStopsAtTheEnd() async
func testSortSwitchResetsTheList() async
func testClosedCommentsShowTheMessage() async
func testLikeIsOptimisticAndRollsBack() async
func testThreadLoadsAndPages() async
func testDeleteRemovesTheRow() async
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `comments` (10), `comments-thread` (13) and `picture-viewer`. Compare and fix.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Comments: list, sort, pinned, rich text with emotes, pictures, threads, like and delete"`

### Task 25: Comment composer and emote panel

**Files:**
- Create: `ios/Sources/App/Comments/ComposerModel.swift`, `Composer.swift`, `EmotePanel.swift`, `RecentEmotes.swift`, `ios/Tests/AppTests/ComposerModelTests.swift`
- Modify: `CommentsTab.swift`, `ThreadView.swift`, `CommentRow.swift` (回复 opens the composer)

**Interfaces:**
- `enum ReplyTarget: Equatable { case video, comment(Comment), threadReply(root: Comment, reply: Comment) }`
- `@MainActor @Observable final class ComposerModel`:
  - `init(client: BiliClient, aid: Int64, target: ReplyTarget, comments: CommentsModel)`.
  - `var text: String`, `var syncToDynamic = false`, `var showingEmotes = false`, `var placeholder: String` ("回复 名字:" for replies; otherwise "哎呦，不错哦，发条评论吧").
  - `func insert(_ emote: Emote)` inserts at the end, and records it in `RecentEmotes`.
  - `func post() async -> Bool`. The fields it sends:
    - `.video`: no root and no parent.
    - `.comment(c)`: `root = parent = c.rpid`.
    - `.threadReply(root, reply)`: `root = root.rpid`, `parent = reply.rpid`, with the message prefixed "回复 @<reply.member.name> :".
  - On success it inserts the comment into the list or thread and clears the draft. On failure it keeps the text and toasts the message.
  - Drafts are kept per target in memory for the page's life.
- `enum RecentEmotes { static func list(defaults: UserDefaults = .standard) -> [Emote]; static func record(_ e: Emote, defaults: UserDefaults = .standard) }`: most recent first, at most 14, de-duplicated by token, stored as JSON under `emotes.recent`.
- `Composer` (14): a white sheet over the dimmed page; the text field with the placeholder; an expand arrow (switches to a taller editor); a toolbar with "○ 转到动态", the keyboard/emote toggle (pink when emotes show), and 发布 (pink when there is text, faded otherwise). The @ and ⊕ buttons are not shown.
- `EmotePanel` (14): 最近使用, then 所有表情 for the selected package in a 7-column grid (large packages in 4 columns); package tabs along the bottom using the package icons (颜文字 shown as text). `emotePackages()` is loaded once per app run and cached in `AppEnvironment`.
- Logged out: tapping the bottom bar asks for login instead of opening the composer.

- [ ] **Step 1: Write the failing tests:**

```swift
func testTopLevelPostSendsNoRootOrParent() async
func testReplyToACommentUsesItForRootAndParent() async
func testReplyInsideAThreadPrefixesTheNameAndSplitsRootAndParent() async   // message "回复 @小明 :好" , root 10, parent 11
func testFailedPostKeepsTheDraft() async
func testRecentEmotesAreMostRecentFirstAndCapped()
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** `composer-emotes` (14). Compare it with the reference.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "Comment composer with the emote panel, replies and threads"`

### Task 26: 首页 and 历史记录

**Files:**
- Create: `ios/Sources/App/Home/FeedModel.swift`, `FeedCard.swift`, `AvatarMenu.swift`, `ios/Sources/App/History/HistoryModel.swift`, `HistoryView.swift`, `ios/Tests/AppTests/FeedModelTests.swift`, `HistoryModelTests.swift`
- Modify: `ios/Sources/App/Home/HomeView.swift` (rewritten; keeps `open(_:)`'s link handling and the part picker)

**Interfaces:**
- `@MainActor @Observable final class FeedModel`:
  - `init(client: BiliClient)`; `cards: [FeedCard]`, `loading`, `error`.
  - `func refresh() async` (index 1, replaces the list) and `func loadMore() async` (next index, de-duplicated by bvid).
- `HomeView` (01):
  - Top row: the avatar (account face, or a grey placeholder) opening `AvatarMenu`, and a rounded field with the placeholder "粘贴链接或BV号". Submitting the field, or pasting into it, runs the existing link parsing and opens a `VideoPageView`.
  - A tab row with only 推荐, selected.
  - A 2-column grid of `FeedCard`s on `Theme.pageGrey`, with pull to refresh and endless scroll.
- `FeedCard`: a 16:10 cover with a bottom gradient, ▶ play count, danmaku count and duration; a 2-line title; and a footer.
  - The footer shows the `reason` as a pink-tint pill, or a 竖屏 tag when vertical, or an "UP" badge; then the uploader name and ⋮.
  - ⋮ offers 稍后再看.
  - A tap opens the video.
- `AvatarMenu`: the account row from M1 (name, 大会员, 退出 or 登录), 历史记录 (pushes `HistoryView`), 最近打开 (the M1 recents list as a pushed page), 设置 (the existing `SettingsView` sheet).
- `@MainActor @Observable final class HistoryModel`: `init(client: BiliClient)`; `sections`; `func loadMore() async`; `isEnd`.
- `HistoryView` (28):
  - Title 历史记录, no chips, sections from `HistoryGrouping`.
  - Rows: the cover with "00:02/02:12" (or 已看完) on it, the title, "UP name", the device icon and `HH:mm` (or the date for older sections).
  - A tap opens `VideoRoute(bvid:cid:startSeconds:)`, starting at 0 when the video was finished.
  - Logged out, it shows "登录后查看历史记录" and a login button.

- [ ] **Step 1: Write the failing tests:**

```swift
func testRefreshReplacesAndLoadMoreAppendsWithoutDuplicates() async
func testHistoryPagesUntilEmpty() async
func testFinishedHistoryItemOpensAtTheStart()
```

- [ ] **Step 2: Implement.**
- [ ] **Step 3: Shots.** Replace `01-first-launch` with the new home (demo data) and add `history`. Compare with 01 and 28.
- [ ] **Step 4: Push and watch the compile check.**
- [ ] **Step 5: Commit and push.** `git commit -m "首页 with the 推荐 feed and avatar menu; 历史记录 page"`

### Task 27: Ship build B

**Files:**
- Modify: `docs/m2-phone-checklist.md` (section "Build B"), `CLAUDE.md` (Status; the Next line points at milestone 3), `docs/background.md` (what the dislike call needed, any risk-control findings), `docs/superpowers/specs/2026-10-16-m1-playback-core-design.md` §15 (add: decide about the borrowed PiliPlus art and font in `ios/Resources/Borrowed/` before a public release)

- [ ] **Step 1: Write the build B checklist.** Numbered steps:
  - The 推荐 feed: refresh and scroll.
  - The avatar menu, 历史记录 and 最近打开.
  - Open a video and check 简介 (expand, timestamps seek, 合集 sheet, 分P list, related opens a new page and back returns).
  - Every action, logged in and logged out. 三连 by holding. The coin dialog, both amounts, 同时点赞. Favourites: tick, untick and a new folder; check them in the official app. Share. Follow and unfollow.
  - 不喜欢: the confirm page, then the toggle.
  - Comments: sort, a thread, a picture, posting a comment and a reply with emotes (check them in the official app), like, 踩, and delete own.
  - Full-screen actions in landscape and 竖屏.
  - The collapsing player while paused.
- [ ] **Step 2: Check that KaiC added `BILI_APP_KEYS`** (`gh secret list -R KaiC5504/BiliNative`). If it is missing, ask KaiC to add it first (Task 19 Step 3), since without it 不喜欢 stays greyed out.
- [ ] **Step 3: Run the BiliCore suite and the Python tests on the PC**, both green.
- [ ] **Step 4: Merge to main and ship** (Global Constraints), and look at every screenshot on the `main` run.
- [ ] **Step 5: Report to KaiC:** the build number, what changed, and the checklist. Commit and push the docs.
