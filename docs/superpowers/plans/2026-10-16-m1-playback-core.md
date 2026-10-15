# BiliNative Milestone 1 (Playback Core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native iOS app that logs in to Bilibili, opens a pasted video link, and plays it through AVPlayer fed by an in-app HLS server running a Swift port of the BTR multi-node download engine, with a direct-CDN fallback, a BTR on/off switch, a stats overlay and log streaming to KaiC's PC.

**Architecture:** All logic that does not need iOS lives in the Swift package `BiliCore` (modules `BiliShared`, `DevLog`, `BiliAPI`, `DashHLS`, `Ripper`, `LocalHTTP`, plus the `ripper-bench` command line tool) and is built and tested with `swift test` on Windows and on macOS CI. The iOS app (`BiliNative`, SwiftUI) only adds screens, the Keychain, the login web view, the Network.framework socket server, the AVFoundation glue and the dev-tools networking. The project follows KaiC's ios-testflight pipeline: XcodeGen project under `ios/`, GitHub Actions on `macos-26`, TestFlight internal testing.

**Tech Stack:** Swift (latest stable toolchain on Windows; Xcode 26.6 on CI), SwiftPM tools 6.0 in Swift 5 language mode, XCTest, SwiftUI, AVFoundation/AVKit, WebKit, Network.framework, Security (Keychain), XcodeGen, GitHub Actions, Python 3.13 via `uv` for the PC log receiver and helper scripts, Pillow for icons, ffmpeg on CI for test media.

**Spec:** `docs/superpowers/specs/2026-10-16-m1-playback-core-design.md` (read it before starting any task).

**Layout note:** the spec sketches `App/` and `Packages/BiliCore/` at the repo root. The ios-testflight templates put the iOS project under `ios/`, so this plan uses `ios/Sources/App/` and `ios/Packages/BiliCore/`. Nothing else changes.

## Global Constraints

- Repo: `D:\Repos\Apps\BiliNative`, GitHub `KaiC5504/BiliNative`, **public** from the first push (free Mac minutes). Never commit secrets, cookies or `logs/`.
- iOS deployment target `26.0`. CI runner `macos-26`, newest Xcode on the image (26.6 on 2026-10-16). KaiC's phone is an iPhone 17 Pro Max on iOS 27.
- Internal target and scheme name `BiliNative`; bundle id `com.kaichuan.bilinative`; display name from Task 2 (default `BiliNative`).
- `BiliCore`: Foundation only, no third-party packages; `// swift-tools-version:6.0`, `swiftLanguageModes: [.v5]`; tests use XCTest; every module must build and pass `swift test` on Windows and macOS.
- App target: Swift 5 language mode (template setting), SwiftUI with UIKit wrappers only for `AVPlayerViewController` and `WKWebView`; no third-party dependencies.
- No code copied from ATV-Bilibili-demo (GPL-2.0) or PiliPlus (GPL-3.0). The BTR port keeps BTR's MIT licence text in `ios/Packages/BiliCore/Sources/Ripper/LICENSE-BTR.txt`.
- UI text in Simplified Chinese; `developmentLanguage: zh-Hans`; a String Catalog `Localizable.xcstrings` exists in the app target.
- Never log cookie values, `SESSDATA`, `bili_jct`/CSRF, Authorization headers or passwords. Signed CDN URLs are logged as host + path + `deadline` only. The network log sink is compiled only when `DEV_TOOLS` is set.
- Every playback failure must end in slower playback (direct mode, another codec) or a clear Chinese message, never a stuck player.
- Comments: sparse, explain why not what (KaiC's global CLAUDE.md). No attribution lines in commit messages.
- Engine defaults copied from BTR 2026.10.8.1: first byte 5.5 s, stalled stream 4 s, attempt 15 s, hedge 900 ms, 3 rounds within 25 s, minimum piece 64 KiB, speed samples only from transfers of at least 48 KiB, resume only from prefixes of at least 32 KiB, auto ladder 8/12/16/24/32/48/64 starting at 16.

## Review Focus

1. **Text shared from the official app** (title in 【】 brackets, full-width punctuation, a b23.tv link in the middle, trailing text) must open the right video. Pinned in Task 6.
2. **Videos without DASH** (old FLV-only uploads, `durl` responses) must give the message "这个视频不是 DASH 格式，暂不支持", not a crash. Pinned in Tasks 7 and 8 (and shown by the controller in Task 25).
3. **Bilibili field-name variants** (`baseUrl`/`base_url`, `backupUrl` null, `SegmentBase`/`segment_base`, missing `frameRate`) must decode. Pinned in Task 7.
4. **AVPlayer Range requests that are not segment-aligned**, open-ended (`bytes=a-`), suffix (`bytes=-n`) or straddle the in-memory init bytes must be answered correctly. Pinned in Task 21.
5. **A network blip** (every node fails for about 0.4 s, e.g. Wi-Fi to cellular) must be ridden out by the retry rounds, not turned into a fatal fallback. Pinned in Task 18.

---

## File Structure

```
BiliNative/
  .gitattributes, .gitignore
  .github/workflows/core-tests.yml        swift test for BiliCore on macOS
  .github/workflows/ios-compile.yml       simulator build, integration tests, screenshots
  .github/workflows/testflight.yml        signed build and upload (from the skill template)
  scripts/testflight.py                   from the ios-testflight skill
  scripts/testflight-requirements.txt     from the ios-testflight skill
  scripts/icons.py                        icon concepts and AppIcon installer
  tools/logserver.py                      PC log receiver
  tools/test_logserver.py                 its tests
  design/icons/                           concept PNGs, CHOICES.md
  ios/project.yml                         XcodeGen spec
  ios/scripts/make_test_media.py          ffmpeg test media for CI
  ios/Sources/App/                        the iOS app (files listed in Tasks 22-28)
  ios/Resources/                          Assets.xcassets, Localizable.xcstrings
  ios/Tests/AppTests/                     simulator integration tests
  ios/Packages/BiliCore/
    Package.swift
    Sources/BiliShared/   ByteRange.swift, MediaSegment.swift, Locked.swift, MonotonicClock.swift
    Sources/DevLog/       LogEvent.swift, Logger.swift, Redactor.swift, MemorySink.swift, FileSink.swift, NetworkSink.swift, Replay.swift
    Sources/BiliAPI/      MD5.swift, WBI.swift, LinkParser.swift, Models.swift, HTTP.swift, CookieJar.swift, BiliClient.swift, BiliError.swift
    Sources/DashHLS/      BoxReader.swift, SidxParser.swift, InitSegmentFixer.swift, CodecMapper.swift, PlaylistBuilder.swift, TrackSelector.swift
    Sources/Ripper/       NodeCatalog.swift, BanList.swift, Resolver.swift, AutoConcurrency.swift, ConnectionPool.swift,
                          Transport.swift, Meter.swift, EngineStats.swift, Attempt.swift, PieceDownloader.swift,
                          PrimaryAssigner.swift, RangeDownloader.swift, RipperSession.swift, URLSessionRangeTransport.swift, LICENSE-BTR.txt
    Sources/LocalHTTP/    HTTPRequestParser.swift, HTTPResponseWriter.swift, RangeRequest.swift, PlaybackRouter.swift
    Sources/ripper-bench/ Bench.swift
    Tests/<Module>Tests/  one test target per module
```

Boundaries: `BiliShared` has no dependencies. `DevLog` depends on `BiliShared`. `BiliAPI`, `Ripper` depend on `BiliShared` and `DevLog`. `DashHLS` and `LocalHTTP` depend on `BiliShared` only. The app depends on all of them. `DashHLS` never imports `Ripper` and vice versa; the shared `MediaSegment` type lives in `BiliShared`.

---

### Task 1: Toolchain, repository and the BiliShared module

**Files:**
- Create: `.gitattributes`, `.github/workflows/core-tests.yml`
- Modify: `.gitignore`
- Create: `ios/Packages/BiliCore/Package.swift`
- Create: `ios/Packages/BiliCore/Sources/BiliShared/ByteRange.swift`, `MediaSegment.swift`, `Locked.swift`, `MonotonicClock.swift`
- Test: `ios/Packages/BiliCore/Tests/BiliSharedTests/ByteRangeTests.swift`, `LockedTests.swift`

**Interfaces:**
- Produces: `ByteRange` (`start`, `end` inclusive, `length`, `headerValue`, `parse(_:)`, `split(concurrency:minChunk:)`, `contains(_:)`), `ContentRange` (`range`, `total`, `parse(_:)`), `MediaSegment` (`index`, `range`, `startTime`, `duration`), `Locked<Value>` (`withLock`, `current`), `MonotonicClock` (`nowMs`, `.system`), `ManualClock` (`advance`, `set`, `clock`), `sleepMs(_:)`.

- [ ] **Step 1: Install the Swift toolchain on Windows (ask KaiC first)**

The toolchain is not installed (checked 2026-10-16). Ask KaiC for a go-ahead, then follow the current instructions at https://www.swift.org/install/windows/ (they list the Visual Studio components and the `winget install --id Swift.Toolchain -e` line; use the latest stable release they name). Afterwards, in a new PowerShell:

Run: `swift --version`
Expected: a stable `Swift version 6.x` line.

Remind KaiC that Sideloadly must keep being started from `D:\Tools\Sideloadly\Sideloadly (Swift-safe).cmd`, because Swift's `Foundation.dll` on PATH breaks Sideloadly's login otherwise.

- [ ] **Step 2: Repository housekeeping**

Create `.gitattributes`:

```
* text=auto eol=lf
*.png binary
*.mp4 binary
```

Append to `.gitignore` (it already ignores `logs/`, `.build/`, `.swiftpm/`, `*.xcodeproj/`, `DerivedData/`, cookie files):

```
ios/Generated/
ios/build/
__pycache__/
design/icons/*.tmp.png
```

- [ ] **Step 3: Create the package manifest**

`ios/Packages/BiliCore/Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BiliCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "BiliCore", targets: ["BiliShared"]),
    ],
    targets: [
        .target(name: "BiliShared"),
        .testTarget(name: "BiliSharedTests", dependencies: ["BiliShared"]),
    ],
    swiftLanguageModes: [.v5]
)
```

Later tasks add their targets to `targets:` and their module names to the `BiliCore` library product's `targets:` list.

- [ ] **Step 4: Write the failing tests**

`Tests/BiliSharedTests/ByteRangeTests.swift`:

```swift
import XCTest
@testable import BiliShared

final class ByteRangeTests: XCTestCase {
    func testParseBilibiliNotation() {
        XCTAssertEqual(ByteRange.parse("0-1234"), ByteRange(start: 0, end: 1234))
        XCTAssertEqual(ByteRange.parse("0-1234")?.length, 1235)
        XCTAssertNil(ByteRange.parse("12-3"))
        XCTAssertNil(ByteRange.parse("abc"))
        XCTAssertNil(ByteRange(start: -1, end: 4))
    }

    func testHeaderValueAndContains() {
        let outer = ByteRange(start: 10, end: 99)!
        XCTAssertEqual(outer.headerValue, "bytes=10-99")
        XCTAssertTrue(outer.contains(ByteRange(start: 20, end: 30)!))
        XCTAssertFalse(outer.contains(ByteRange(start: 90, end: 100)!))
    }

    func testContentRange() {
        let parsed = ContentRange.parse("bytes 100-199/1000")
        XCTAssertEqual(parsed?.range, ByteRange(start: 100, end: 199))
        XCTAssertEqual(parsed?.total, 1000)
        XCTAssertNotNil(ContentRange.parse("bytes 0-9/*"))
        XCTAssertNil(ContentRange.parse("bytes 0-9/*")?.total)
        XCTAssertNil(ContentRange.parse("bytes 0-9/5"))
        XCTAssertNil(ContentRange.parse("items 0-9/50"))
        XCTAssertNil(ContentRange.parse(nil))
    }

    func testSplitMatchesBTR() {
        let mebibyte = ByteRange(start: 0, end: 1_048_575)!
        XCTAssertEqual(mebibyte.split(concurrency: 4, minChunk: 65_536).map(\.length), [262_144, 262_144, 262_144, 262_144])
        XCTAssertEqual(ByteRange(start: 0, end: 99)!.split(concurrency: 8, minChunk: 65_536).count, 1)
        let odd = ByteRange(start: 10, end: 100_010)!
        let parts = odd.split(concurrency: 3, minChunk: 32_768)
        XCTAssertEqual(parts.map(\.length), [33_334, 33_334, 33_333])
        XCTAssertEqual(parts.first?.start, 10)
        XCTAssertEqual(parts.last?.end, 100_010)
    }
}
```

`Tests/BiliSharedTests/LockedTests.swift`:

```swift
import XCTest
import Dispatch
@testable import BiliShared

final class LockedTests: XCTestCase {
    func testConcurrentIncrements() {
        let counter = Locked(0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in counter.withLock { $0 += 1 } }
        XCTAssertEqual(counter.current, 1000)
    }

    func testManualClock() {
        let manual = ManualClock(100)
        XCTAssertEqual(manual.clock.nowMs(), 100)
        manual.advance(50)
        XCTAssertEqual(manual.clock.nowMs(), 150)
        manual.set(10)
        XCTAssertEqual(manual.clock.nowMs(), 10)
    }
}
```

- [ ] **Step 5: Run the tests to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore`
Expected: compile errors, `cannot find 'ByteRange' in scope`.

- [ ] **Step 6: Implement BiliShared**

`Sources/BiliShared/ByteRange.swift`:

```swift
import Foundation

public struct ByteRange: Hashable, Sendable, CustomStringConvertible {
    public let start: Int64
    /// Inclusive, like HTTP Range and Bilibili's SegmentBase notation.
    public let end: Int64

    public init?(start: Int64, end: Int64) {
        guard start >= 0, end >= start else { return nil }
        self.start = start
        self.end = end
    }

    public var length: Int64 { end - start + 1 }
    public var description: String { "\(start)-\(end)" }
    public var headerValue: String { "bytes=\(start)-\(end)" }

    public func contains(_ other: ByteRange) -> Bool {
        other.start >= start && other.end <= end
    }

    /// Bilibili's "a-b" notation from SegmentBase.
    public static func parse(_ text: String) -> ByteRange? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int64(parts[0]), let end = Int64(parts[1]) else { return nil }
        return ByteRange(start: start, end: end)
    }

    /// BTR range-core `splitRange`: at most `concurrency` pieces, none smaller than `minChunk`
    /// (and never below 32 KiB), sizes differing by at most one byte.
    public func split(concurrency: Int, minChunk: Int64) -> [ByteRange] {
        let limit = Int64(max(1, min(512, concurrency)))
        let minimum = max(32 * 1024, minChunk)
        let count = max(1, min(limit, (length + minimum - 1) / minimum))
        let base = length / count
        let remainder = length % count
        var pieces: [ByteRange] = []
        var cursor = start
        for index in 0..<count {
            let size = base + (index < remainder ? 1 : 0)
            pieces.append(ByteRange(start: cursor, end: cursor + size - 1)!)
            cursor += size
        }
        return pieces
    }
}

public struct ContentRange: Equatable, Sendable {
    public let range: ByteRange
    public let total: Int64?

    public init(range: ByteRange, total: Int64?) {
        self.range = range
        self.total = total
    }

    /// "bytes a-b/total" or "bytes a-b/*".
    public static func parse(_ text: String?) -> ContentRange? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), text.hasPrefix("bytes ") else { return nil }
        let halves = text.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2, let range = ByteRange.parse(String(halves[0])) else { return nil }
        if halves[1] == "*" { return ContentRange(range: range, total: nil) }
        guard let total = Int64(halves[1]), total > range.end else { return nil }
        return ContentRange(range: range, total: total)
    }
}
```

`Sources/BiliShared/MediaSegment.swift`:

```swift
public struct MediaSegment: Hashable, Sendable {
    public let index: Int
    public let range: ByteRange
    /// Seconds from the start of the presentation.
    public let startTime: Double
    public let duration: Double

    public init(index: Int, range: ByteRange, startTime: Double, duration: Double) {
        self.index = index
        self.range = range
        self.startTime = startTime
        self.duration = duration
    }

    public var endTime: Double { startTime + duration }
}
```

`Sources/BiliShared/Locked.swift`:

```swift
import Foundation

public final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    public var current: Value { withLock { $0 } }
}
```

`Sources/BiliShared/MonotonicClock.swift`:

```swift
import Foundation

public struct MonotonicClock: Sendable {
    public let nowMs: @Sendable () -> Double

    public init(nowMs: @escaping @Sendable () -> Double) {
        self.nowMs = nowMs
    }

    public static let system = MonotonicClock { ProcessInfo.processInfo.systemUptime * 1000 }
}

/// Test clock whose time only moves when told to.
public final class ManualClock: @unchecked Sendable {
    private let value: Locked<Double>

    public init(_ start: Double = 0) {
        value = Locked(start)
    }

    public func advance(_ ms: Double) { value.withLock { $0 += ms } }
    public func set(_ ms: Double) { value.withLock { $0 = ms } }
    public var clock: MonotonicClock { MonotonicClock { [value] in value.current } }
}

public func sleepMs(_ ms: Double) async throws {
    guard ms > 0 else {
        try Task.checkCancellation()
        return
    }
    try await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 8: Add the core-tests workflow**

`.github/workflows/core-tests.yml`:

```yaml
name: Core tests

on:
  push:
    paths:
      - "ios/Packages/**"
      - ".github/workflows/core-tests.yml"
  pull_request:
    paths:
      - "ios/Packages/**"
  workflow_dispatch:

concurrency:
  group: core-tests-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Toolchain
        run: |
          NEWEST=$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1)
          if [ -n "$NEWEST" ]; then sudo xcode-select -s "$NEWEST"; fi
          swift --version
      - name: swift test
        run: swift test --package-path ios/Packages/BiliCore
```

- [ ] **Step 9: Commit and create the public GitHub repo**

```bash
git add .gitattributes .gitignore .github/workflows/core-tests.yml ios/Packages/BiliCore
git commit -m "Add BiliCore package with BiliShared and core test workflow"
gh repo create KaiC5504/BiliNative --public --source . --push
```

Expected: the push succeeds and the "Core tests" workflow turns green on GitHub (`gh run watch` or `gh run list --limit 1`).

---

### Task 2: App name and icon concepts

KaiC picks the display name and the icon. This task produces the choices and an installer; it does not block the engine tasks.

**Files:**
- Create: `scripts/icons.py`
- Create: `design/icons/concept-1.png` … `concept-4.png` (generated), `design/CHOICES.md`

**Interfaces:**
- Produces: `uv run scripts/icons.py --apply N` writes `ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (RGB, no alpha) and its `Contents.json`. Task 21 calls it.

- [ ] **Step 1: Write the icon script**

`scripts/icons.py`:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
"""Draws the app icon concepts and installs the chosen one into the asset catalog."""
import argparse
import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "design" / "icons"
APPICON = ROOT / "ios" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024


def vertical_gradient(top, bottom):
    image = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(image)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line([(0, y), (SIZE, y)], fill=color)
    return image


def play_triangle(draw, cx, cy, size, fill):
    half = size / 2
    points = [(cx - half * 0.8, cy - half), (cx - half * 0.8, cy + half), (cx + half, cy)]
    draw.polygon(points, fill=fill)


def concept_threads():
    image = vertical_gradient((20, 16, 48), (52, 20, 84))
    glow = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(glow)
    colors = [(251, 114, 153), (236, 120, 190), (190, 130, 240), (120, 170, 250), (90, 210, 240)]
    for i, color in enumerate(colors):
        y = 330 + i * 90
        draw.line([(140, y), (560, y + (512 - y) * 0.55)], fill=color, width=34)
    glow = glow.filter(ImageFilter.GaussianBlur(10))
    image = Image.blend(image, glow, 0.55)
    draw = ImageDraw.Draw(image)
    for i, color in enumerate(colors):
        y = 330 + i * 90
        draw.line([(140, y), (560, y + (512 - y) * 0.55)], fill=color, width=22)
    play_triangle(draw, 680, 512, 330, (255, 255, 255))
    return image


def concept_bolt():
    image = vertical_gradient((255, 128, 168), (214, 60, 120))
    draw = ImageDraw.Draw(image)
    play_triangle(draw, 540, 512, 520, (255, 255, 255))
    cut = [(470, 250), (600, 250), (520, 470), (640, 470), (420, 800), (480, 560), (380, 560)]
    draw.polygon(cut, fill=(214, 60, 120))
    return image


def concept_orbit():
    image = vertical_gradient((10, 12, 30), (24, 18, 56))
    glow = Image.new("RGB", (SIZE, SIZE))
    draw = ImageDraw.Draw(glow)
    for radius, color in [(390, (251, 114, 153)), (310, (160, 120, 250)), (230, (90, 200, 240))]:
        box = [512 - radius, 512 - radius, 512 + radius, 512 + radius]
        draw.arc(box, start=200, end=520, fill=color, width=26)
        angle = math.radians(520 % 360)
        dot = (512 + radius * math.cos(angle), 512 + radius * math.sin(angle))
        draw.ellipse([dot[0] - 30, dot[1] - 30, dot[0] + 30, dot[1] + 30], fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(6))
    image = Image.blend(image, glow, 0.85)
    play_triangle(ImageDraw.Draw(image), 530, 512, 230, (255, 255, 255))
    return image


def concept_glass():
    image = vertical_gradient((60, 30, 110), (12, 10, 30))
    orb = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(orb).ellipse([212, 212, 812, 812], fill=(255, 255, 255))
    orb = orb.filter(ImageFilter.GaussianBlur(4))
    mask = orb.convert("L").point(lambda v: int(v * 0.32))
    image.paste((235, 225, 255), mask=mask)
    draw = ImageDraw.Draw(image)
    draw.arc([212, 212, 812, 812], start=200, end=330, fill=(255, 255, 255), width=10)
    play_triangle(draw, 530, 512, 300, (251, 114, 153))
    return image


CONCEPTS = {1: concept_threads, 2: concept_bolt, 3: concept_orbit, 4: concept_glass}


def render_all():
    OUT.mkdir(parents=True, exist_ok=True)
    for number, make in CONCEPTS.items():
        path = OUT / f"concept-{number}.png"
        make().convert("RGB").save(path)
        print(path)


def apply(number):
    APPICON.mkdir(parents=True, exist_ok=True)
    CONCEPTS[number]().convert("RGB").save(APPICON / "icon-1024.png")
    contents = {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }
    (APPICON / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")
    catalog = APPICON.parent / "Contents.json"
    if not catalog.exists():
        catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", encoding="utf-8")
    print(APPICON / "icon-1024.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", type=int, choices=sorted(CONCEPTS))
    args = parser.parse_args()
    if args.apply:
        apply(args.apply)
    else:
        render_all()
```

- [ ] **Step 2: Render the concepts and check them**

Run: `uv run scripts/icons.py`
Expected: four paths printed. Open each PNG (Read tool) and check it is 1024x1024, has no transparency and nothing is drawn off-canvas. Fix coordinates if a shape is clipped.

- [ ] **Step 3: Write the choices file**

`design/CHOICES.md`:

```markdown
# Name and icon

Icon concepts (design/icons):
1. Threads: five coloured lines converging into a play button (the multi-node download).
2. Bolt: pink tile with a play button cut by a lightning bolt.
3. Orbit: three node arcs orbiting a play button.
4. Glass: a frosted glass orb with a pink play button.

Name ideas (shown under the icon; avoid "Bili"/"哔哩" for the public release):
- Riptide
- Threadline
- 线速 (Xiansu)
- Kairo
- 疾影 (Jiying)

Chosen icon: (KaiC fills in)
Chosen name: (KaiC fills in)
```

- [ ] **Step 4: Show KaiC and record the choice**

Send the four PNGs with SendUserFile and ask which icon and name he wants. Write his answers into `design/CHOICES.md`. If he wants changes to a concept, adjust that function and re-render. If he has not answered by the time Task 21 runs, Task 21 installs concept 1 and the name `BiliNative`.

- [ ] **Step 5: Commit**

```bash
git add scripts/icons.py design/
git commit -m "Add icon concepts and name ideas"
```

---
### Task 3: DevLog (structured logging, redaction, file and network sinks)

**Files:**
- Modify: `ios/Packages/BiliCore/Package.swift`
- Create: `Sources/DevLog/LogEvent.swift`, `Logger.swift`, `Redactor.swift`, `MemorySink.swift`, `FileSink.swift`, `NetworkSink.swift`, `Replay.swift`
- Test: `Tests/DevLogTests/RedactorTests.swift`, `LoggerTests.swift`, `FileSinkTests.swift`, `NetworkSinkTests.swift`

(Paths in this and later package tasks are relative to `ios/Packages/BiliCore/`.)

**Interfaces:**
- Consumes: `Locked`, `sleepMs` from BiliShared.
- Produces:
  - `LogLevel` (`debug`, `info`, `warn`, `error`), `LogCategory` (`app`, `api`, `engine`, `server`, `player`, `ui`), `LogValue` (literal-expressible; `init(_:)` for `String`, `Int`, `Int64`, `Double`, `Bool`), `LogEvent(t:seq:session:level:cat:msg:f:)`.
  - `protocol LogSink: AnyObject { func receive(_ event: LogEvent) }`.
  - `Logger` (`shared`, `session`, `add(_:)`, `remove(_:)`, `log(_:_:_:_:)`, `debug/info/warn/error(_ cat:, _ msg:, _ fields: = [:])`).
  - `Redactor.fields(_:)`, `Redactor.text(_:)`, `Redactor.url(_:)`, `Redactor.mid(_:)`.
  - `MemorySink.events`; `FileSink(directory:session:maxTotalBytes:)` with `fileURL`, `flush()`, `sessionFiles()`, `exportFile()`, `static readEvents(_:)`; `NetworkSink(poster:intervalMs:maxBuffered:batchLimit:)` with `start()`, `stop()`, `flushOnce()`, `enqueue(_:)`, `pending`, `state`, `onAcknowledged`; `AckStore(url:)`; `ReplayPlanner.unsent(files:currentSession:ack:)`.

- [ ] **Step 1: Register the module**

In `Package.swift` add `"DevLog"` to the `BiliCore` product's `targets:` and add to `targets:`:

```swift
        .target(name: "DevLog", dependencies: ["BiliShared"]),
        .testTarget(name: "DevLogTests", dependencies: ["DevLog", "BiliShared"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/DevLogTests/RedactorTests.swift`:

```swift
import XCTest
@testable import DevLog

final class RedactorTests: XCTestCase {
    func testSecretFieldsAreRedacted() {
        let out = Redactor.fields(["SESSDATA": "abc", "Cookie": "x=y", "node": "upos-sz-mirrorcosov.bilivideo.com"])
        XCTAssertEqual(out["SESSDATA"], .string("[redacted]"))
        XCTAssertEqual(out["Cookie"], .string("[redacted]"))
        XCTAssertEqual(out["node"], .string("upos-sz-mirrorcosov.bilivideo.com"))
    }

    func testSignedURLKeepsHostPathAndDeadline() {
        let url = "https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?e=ig8euxZM&uipk=5&deadline=1760000000&gen=playurlv2&os=cosovbv&upsig=deadbeef&mid=99887766"
        XCTAssertEqual(
            Redactor.text("GET \(url) done"),
            "GET https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/12/34/567/567-1-100050.m4s?deadline=1760000000 done"
        )
    }

    func testCookiePairsInFreeText() {
        XCTAssertEqual(
            Redactor.text("Cookie: SESSDATA=abc%2C123; bili_jct=ff00; buvid3=keep"),
            "Cookie: SESSDATA=[redacted]; bili_jct=[redacted]; buvid3=keep"
        )
    }

    func testMidHash() {
        XCTAssertEqual(Redactor.mid(12345), Redactor.mid(12345))
        XCTAssertFalse(Redactor.mid(12345).contains("12345"))
        XCTAssertTrue(Redactor.mid(12345).hasPrefix("mid:"))
    }
}
```

`Tests/DevLogTests/LoggerTests.swift`:

```swift
import XCTest
@testable import DevLog

final class LoggerTests: XCTestCase {
    func testDeliversToSinksWithIncreasingSeq() {
        let logger = Logger(session: "s1")
        let sink = MemorySink()
        logger.add(sink)
        logger.info(.engine, "piece", ["bytes": 65536, "node": "a"])
        logger.warn(.api, "Cookie: SESSDATA=x")
        XCTAssertEqual(sink.events.map(\.seq), [1, 2])
        XCTAssertEqual(sink.events[0].f["bytes"], .int(65536))
        XCTAssertEqual(sink.events[0].session, "s1")
        XCTAssertEqual(sink.events[1].level, .warn)
        XCTAssertEqual(sink.events[1].msg, "Cookie: SESSDATA=[redacted]")
        logger.remove(sink)
        logger.info(.app, "after removal")
        XCTAssertEqual(sink.events.count, 2)
    }

    func testEventRoundTrip() throws {
        let event = LogEvent(t: 1.5, seq: 1, session: "s", level: .info, cat: .app, msg: "m",
                             f: ["a": "x", "b": 3, "c": 1.5, "d": true])
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(LogEvent.self, from: data), event)
    }
}
```

`Tests/DevLogTests/FileSinkTests.swift`:

```swift
import XCTest
@testable import DevLog

final class FileSinkTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("devlog-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWritesJSONLinesAndReadsBack() throws {
        let dir = tempDir()
        let sink = try FileSink(directory: dir, session: "aaa")
        let logger = Logger(session: "aaa")
        logger.add(sink)
        logger.info(.app, "one")
        logger.info(.app, "two")
        sink.flush()
        XCTAssertEqual(FileSink.readEvents(sink.fileURL).map(\.msg), ["one", "two"])
    }

    func testPrunesOldestSessionFiles() throws {
        let dir = tempDir()
        let filler = Data(repeating: 0x41, count: 600)
        for (name, year) in [("old", 2020), ("mid", 2021)] {
            let url = dir.appendingPathComponent("\(name).jsonl")
            try filler.write(to: url)
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))!
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        _ = try FileSink(directory: dir, session: "new", maxTotalBytes: 1000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mid.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("new.jsonl").path))
    }

    func testReplaySkipsAcknowledgedEventsAndTheCurrentSession() throws {
        let dir = tempDir()
        let oldSink = try FileSink(directory: dir, session: "s1")
        let oldLogger = Logger(session: "s1")
        oldLogger.add(oldSink)
        oldLogger.info(.app, "a")
        oldLogger.info(.app, "b")
        oldLogger.info(.app, "c")
        oldSink.flush()

        let currentSink = try FileSink(directory: dir, session: "s2")
        let currentLogger = Logger(session: "s2")
        currentLogger.add(currentSink)
        currentLogger.info(.app, "live")
        currentSink.flush()

        let ack = AckStore(url: dir.appendingPathComponent("ack.json"))
        ack.record("s1", 2)
        let unsent = ReplayPlanner.unsent(files: currentSink.sessionFiles(), currentSession: "s2", ack: ack)
        XCTAssertEqual(unsent.map(\.msg), ["c"])
        XCTAssertEqual(AckStore(url: dir.appendingPathComponent("ack.json")).lastSeq("s1"), 2)
    }
}
```

`Tests/DevLogTests/NetworkSinkTests.swift`:

```swift
import XCTest
import BiliShared
@testable import DevLog

private struct Offline: Error {}

final class NetworkSinkTests: XCTestCase {
    private func event(_ seq: Int64) -> LogEvent {
        LogEvent(t: 0, seq: seq, session: "s", level: .info, cat: .app, msg: "m\(seq)", f: [:])
    }

    func testRetriesUntilPosterSucceedsAndAcknowledges() async {
        let attempts = Locked(0)
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in
            let attempt = attempts.withLock { value -> Int in value += 1; return value }
            if attempt == 1 { throw Offline() }
            bodies.withLock { $0.append(data) }
        })
        let acked = Locked<[String: Int64]>([:])
        sink.onAcknowledged = { session, seq in acked.withLock { $0[session] = seq } }
        sink.enqueue([event(1), event(2)])

        let first = await sink.flushOnce()
        XCTAssertFalse(first)
        XCTAssertEqual(sink.pending, 2)
        guard case .failing = sink.state else { return XCTFail("expected failing state") }

        let second = await sink.flushOnce()
        XCTAssertTrue(second)
        XCTAssertEqual(sink.pending, 0)
        XCTAssertEqual(sink.state, .connected)
        let lines = String(decoding: bodies.current[0], as: UTF8.self).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(acked.current["s"], 2)
    }

    func testBufferCapDropsOldest() async {
        let bodies = Locked<[Data]>([])
        let sink = NetworkSink(poster: { data in bodies.withLock { $0.append(data) } }, maxBuffered: 3)
        sink.enqueue((1...5).map(event))
        XCTAssertEqual(sink.pending, 3)
        await sink.flushOnce()
        let seqs = String(decoding: bodies.current[0], as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(LogEvent.self, from: Data($0.utf8)).seq }
        XCTAssertEqual(seqs, [3, 4, 5])
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter DevLogTests`
Expected: compile errors (`cannot find 'Redactor' in scope`).

- [ ] **Step 4: Implement the event types**

`Sources/DevLog/LogEvent.swift`:

```swift
import Foundation

public enum LogLevel: String, Codable, Sendable {
    case debug, info, warn, error
}

public enum LogCategory: String, Codable, Sendable {
    case app, api, engine, server, player, ui
}

public enum LogValue: Codable, Sendable, Equatable,
    ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(_ value: String) { self = .string(value) }
    public init(_ value: Int) { self = .int(Int64(value)) }
    public init(_ value: Int64) { self = .int(value) }
    public init(_ value: Double) { self = .double(value) }
    public init(_ value: Bool) { self = .bool(value) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

public struct LogEvent: Codable, Sendable, Equatable {
    /// Unix time in seconds.
    public var t: Double
    public var seq: Int64
    public var session: String
    public var level: LogLevel
    public var cat: LogCategory
    public var msg: String
    public var f: [String: LogValue]

    public init(t: Double, seq: Int64, session: String, level: LogLevel, cat: LogCategory, msg: String, f: [String: LogValue]) {
        self.t = t
        self.seq = seq
        self.session = session
        self.level = level
        self.cat = cat
        self.msg = msg
        self.f = f
    }
}
```

- [ ] **Step 5: Implement the logger, redactor and memory sink**

`Sources/DevLog/Logger.swift`:

```swift
import Foundation
import BiliShared

public protocol LogSink: AnyObject {
    /// Called on the logging thread; must be thread-safe and quick.
    func receive(_ event: LogEvent)
}

public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    public let session: String
    private let state = Locked<(seq: Int64, sinks: [LogSink])>((0, []))

    public init(session: String = Logger.makeSessionID()) {
        self.session = session
    }

    public static func makeSessionID() -> String {
        let hex = String(UInt64.random(in: 0...UInt64.max), radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    public func add(_ sink: LogSink) {
        state.withLock { $0.sinks.append(sink) }
    }

    public func remove(_ sink: LogSink) {
        state.withLock { $0.sinks.removeAll { $0 === sink } }
    }

    public func log(_ level: LogLevel, _ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) {
        let (seq, sinks) = state.withLock { value -> (Int64, [LogSink]) in
            value.seq += 1
            return (value.seq, value.sinks)
        }
        guard !sinks.isEmpty else { return }
        let event = LogEvent(t: Date().timeIntervalSince1970, seq: seq, session: session, level: level, cat: cat,
                             msg: Redactor.text(msg), f: Redactor.fields(fields))
        for sink in sinks { sink.receive(event) }
    }

    public func debug(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.debug, cat, msg, fields) }
    public func info(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.info, cat, msg, fields) }
    public func warn(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.warn, cat, msg, fields) }
    public func error(_ cat: LogCategory, _ msg: String, _ fields: [String: LogValue] = [:]) { log(.error, cat, msg, fields) }
}
```

`Sources/DevLog/Redactor.swift`:

```swift
import Foundation

public enum Redactor {
    static let secretNames: Set<String> = [
        "sessdata", "bili_jct", "csrf", "cookie", "set-cookie", "authorization", "access_key", "refresh_token", "dedeuserid__ckmd5",
    ]
    private static let urlPattern = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+"#)
    private static let pairPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(SESSDATA|bili_jct|csrf|access_key|refresh_token|DedeUserID__ckMd5)=([^;&\s"]+)"#)

    public static func fields(_ fields: [String: LogValue]) -> [String: LogValue] {
        var result: [String: LogValue] = [:]
        for (key, value) in fields {
            if secretNames.contains(key.lowercased()) {
                result[key] = .string("[redacted]")
            } else if case .string(let text) = value {
                result[key] = .string(Self.text(text))
            } else {
                result[key] = value
            }
        }
        return result
    }

    /// Shortens signed URLs and blanks cookie-style secrets in free text.
    public static func text(_ input: String) -> String {
        let shortened = replace(urlPattern, in: input) { url($0) }
        return replace(pairPattern, in: shortened) { match in
            let name = match.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "secret"
            return "\(name)=[redacted]"
        }
    }

    /// Keeps scheme, host, port, path and the `deadline` parameter: enough to see which node and
    /// when the signature expires, without the signature or the account id.
    public static func url(_ text: String) -> String {
        guard let components = URLComponents(string: text), let host = components.host else { return text }
        var result = "\(components.scheme ?? "https")://\(host)"
        if let port = components.port { result += ":\(port)" }
        result += components.path
        if let deadline = components.queryItems?.first(where: { $0.name == "deadline" })?.value {
            result += "?deadline=\(deadline)"
        }
        return result
    }

    public static func mid(_ mid: Int64) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in String(mid).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "mid:" + String(String(hash, radix: 16).prefix(8))
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, transform: (String) -> String) -> String {
        let ns = NSString(string: text)
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(ns.substring(with: match.range))
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
```

`Sources/DevLog/MemorySink.swift`:

```swift
import BiliShared

public final class MemorySink: LogSink, @unchecked Sendable {
    private let store = Locked<[LogEvent]>([])

    public init() {}

    public func receive(_ event: LogEvent) {
        store.withLock { $0.append(event) }
    }

    public var events: [LogEvent] { store.current }
}
```

- [ ] **Step 6: Implement the file sink and replay**

`Sources/DevLog/FileSink.swift`:

```swift
import Foundation
import Dispatch

/// One JSON-lines file per app session, pruned oldest first to stay under `maxTotalBytes`.
public final class FileSink: LogSink, @unchecked Sendable {
    public let directory: URL
    public let fileURL: URL
    private let maxTotalBytes: Int
    private let queue = DispatchQueue(label: "devlog.filesink")
    private let handle: FileHandle?
    private var writtenSincePrune = 0
    private let encoder = JSONEncoder()

    public init(directory: URL, session: String, maxTotalBytes: Int = 20 << 20) throws {
        self.directory = directory
        self.maxTotalBytes = maxTotalBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(session).jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: fileURL)
        handle?.seekToEndOfFile()
        prune()
    }

    deinit {
        try? handle?.close()
    }

    public func receive(_ event: LogEvent) {
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        queue.async {
            self.handle?.write(line)
            self.writtenSincePrune += line.count
            if self.writtenSincePrune > self.maxTotalBytes / 8 {
                self.writtenSincePrune = 0
                self.prune()
            }
        }
    }

    public func flush() {
        queue.sync { handle?.synchronizeFile() }
    }

    /// Oldest first.
    public func sessionFiles() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (modified($0), $0.lastPathComponent) < (modified($1), $1.lastPathComponent) }
    }

    /// Concatenates every session file into one file for the share sheet.
    public func exportFile() throws -> URL {
        flush()
        let output = directory.deletingLastPathComponent().appendingPathComponent("BiliNative-logs.jsonl")
        var data = Data()
        for file in sessionFiles() {
            data.append((try? Data(contentsOf: file)) ?? Data())
        }
        try data.write(to: output)
        return output
    }

    public static func readEvents(_ url: URL) -> [LogEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(LogEvent.self, from: Data($0)) }
    }

    private func prune() {
        var files = sessionFiles()
        func size(_ url: URL) -> Int {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        }
        var total = files.reduce(0) { $0 + size($1) }
        while total > maxTotalBytes, let oldest = files.first, oldest.lastPathComponent != fileURL.lastPathComponent {
            total -= size(oldest)
            try? FileManager.default.removeItem(at: oldest)
            files.removeFirst()
        }
    }
}
```

`Sources/DevLog/Replay.swift`:

```swift
import Foundation
import BiliShared

/// Highest sequence number per session that the PC confirmed, so a crashed session's tail can be resent.
public final class AckStore: @unchecked Sendable {
    private let url: URL
    private let state: Locked<[String: Int64]>

    public init(url: URL) {
        self.url = url
        let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) }
        state = Locked(stored ?? [:])
    }

    public func lastSeq(_ session: String) -> Int64 {
        state.current[session] ?? 0
    }

    public func record(_ session: String, _ seq: Int64) {
        let snapshot = state.withLock { value -> [String: Int64] in
            if seq > (value[session] ?? 0) { value[session] = seq }
            return value
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url)
        }
    }
}

public enum ReplayPlanner {
    public static func unsent(files: [URL], currentSession: String, ack: AckStore) -> [LogEvent] {
        files
            .filter { $0.deletingPathExtension().lastPathComponent != currentSession }
            .flatMap { FileSink.readEvents($0) }
            .filter { $0.seq > ack.lastSeq($0.session) }
    }
}
```

- [ ] **Step 7: Implement the network sink**

`Sources/DevLog/NetworkSink.swift`:

```swift
import Foundation
import BiliShared

/// Batches events and hands them to `poster` (the app's HTTP POST to the PC) every `intervalMs`.
/// Events stay buffered until a post succeeds.
public final class NetworkSink: LogSink, @unchecked Sendable {
    public typealias Poster = @Sendable (Data) async throws -> Void

    public enum State: Equatable, Sendable {
        case idle
        case connected
        case failing(String)
    }

    private let poster: Poster
    private let intervalMs: Double
    private let maxBuffered: Int
    private let batchLimit: Int
    private let buffer = Locked<[LogEvent]>([])
    private let stateBox = Locked<State>(.idle)
    private let loop = Locked<Task<Void, Never>?>(nil)
    private let encoder = JSONEncoder()
    public var onAcknowledged: (@Sendable (_ session: String, _ seq: Int64) -> Void)?

    public init(poster: @escaping Poster, intervalMs: Double = 500, maxBuffered: Int = 10_000, batchLimit: Int = 2_000) {
        self.poster = poster
        self.intervalMs = intervalMs
        self.maxBuffered = maxBuffered
        self.batchLimit = batchLimit
    }

    public var state: State { stateBox.current }
    public var pending: Int { buffer.current.count }

    public func receive(_ event: LogEvent) {
        enqueue([event])
    }

    public func enqueue(_ events: [LogEvent]) {
        buffer.withLock { value in
            value.append(contentsOf: events)
            if value.count > maxBuffered { value.removeFirst(value.count - maxBuffered) }
        }
    }

    public func start() {
        loop.withLock { task in
            guard task == nil else { return }
            task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.flushOnce()
                    try? await sleepMs(self.intervalMs)
                }
            }
        }
    }

    public func stop() {
        loop.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    @discardableResult
    public func flushOnce() async -> Bool {
        let batch = buffer.withLock { Array($0.prefix(batchLimit)) }
        guard !batch.isEmpty else { return true }
        var body = Data()
        for event in batch {
            guard let line = try? encoder.encode(event) else { continue }
            body.append(line)
            body.append(0x0A)
        }
        do {
            try await poster(body)
        } catch {
            stateBox.withLock { $0 = .failing(String(describing: error)) }
            return false
        }
        // Remove by identity: the buffer may have dropped or gained events while posting.
        let sent = Set(batch.map { "\($0.session)#\($0.seq)" })
        buffer.withLock { value in value.removeAll { sent.contains("\($0.session)#\($0.seq)") } }
        stateBox.withLock { $0 = .connected }
        var latest: [String: Int64] = [:]
        for event in batch { latest[event.session] = max(latest[event.session] ?? 0, event.seq) }
        for (session, seq) in latest { onAcknowledged?(session, seq) }
        return true
    }
}
```

- [ ] **Step 8: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter DevLogTests`
Expected: all DevLog tests pass. Then run the whole suite once (`swift test --package-path ios/Packages/BiliCore`) to make sure nothing else broke.

- [ ] **Step 9: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add DevLog: structured events, redaction, file and network sinks"
```

---

### Task 4: PC log receiver

**Files:**
- Create: `tools/logserver.py`
- Test: `tools/test_logserver.py`

**Interfaces:**
- Produces: `uv run tools/logserver.py [--port 47321] [--no-bonjour] [--quiet]`; accepts `POST /logs` (newline-delimited JSON `LogEvent`s), answers `200 ok`; `GET /health`; writes `logs/YYYY-MM-DD/<session>.jsonl`; advertises `_bilinative-log._tcp` via Bonjour. Python API used by the tests: `make_server(port, root, quiet)`.

- [ ] **Step 1: Write the failing test**

`tools/test_logserver.py`:

```python
import json
import pathlib
import sys
import tempfile
import threading
import unittest
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import logserver  # noqa: E402


class LogServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.server = logserver.make_server(0, self.tmp.name, quiet=True)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.tmp.cleanup()

    def post(self, body):
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}/logs",
            data=body.encode("utf-8"),
            method="POST",
            headers={"Content-Type": "application/x-ndjson"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status

    def test_events_land_in_their_session_file(self):
        events = [
            {"t": 1760000000.5, "seq": 1, "session": "abc123", "level": "info", "cat": "engine", "msg": "piece", "f": {"bytes": 65536}},
            {"t": 1760000001, "seq": 2, "session": "abc123", "level": "warn", "cat": "api", "msg": "slow", "f": {}},
        ]
        self.assertEqual(self.post("\n".join(json.dumps(e) for e in events) + "\n"), 200)
        files = list(pathlib.Path(self.tmp.name).rglob("abc123.jsonl"))
        self.assertEqual(len(files), 1)
        lines = files[0].read_text(encoding="utf-8").splitlines()
        self.assertEqual([json.loads(line)["seq"] for line in lines], [1, 2])

    def test_unparsable_line_is_kept(self):
        self.assertEqual(self.post("not json\n"), 200)
        self.assertEqual(len(list(pathlib.Path(self.tmp.name).rglob("unknown.jsonl"))), 1)

    def test_health(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/health", timeout=5) as response:
            self.assertEqual(response.read(), b"ok")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to see it fail**

Run: `python -m unittest discover -s tools -p "test_*.py" -v`
Expected: `ModuleNotFoundError: No module named 'logserver'`.

- [ ] **Step 3: Implement the receiver**

`tools/logserver.py`:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["zeroconf"]
# ///
"""Receives BiliNative's dev logs over Wi-Fi and writes them to logs/<date>/<session>.jsonl."""
import argparse
import datetime as dt
import json
import pathlib
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVICE_TYPE = "_bilinative-log._tcp.local."
COLORS = {"debug": "\033[90m", "info": "\033[0m", "warn": "\033[33m", "error": "\033[31m"}
RESET = "\033[0m"


def lan_addresses():
    addresses = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            # connect() on UDP sends nothing; it only picks the outbound interface.
            probe.connect(("192.0.2.1", 9))
            addresses.add(probe.getsockname()[0])
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def summarize(event):
    stamp = dt.datetime.fromtimestamp(event.get("t", 0)).strftime("%H:%M:%S.%f")[:-3]
    level = event.get("level", "info")
    fields = " ".join(f"{key}={value}" for key, value in sorted(event.get("f", {}).items()))
    return f"{COLORS.get(level, '')}{stamp} {level:<5} {event.get('cat', '?'):<6} {event.get('msg', '')} {fields}{RESET}"


class LogStore:
    def __init__(self, root):
        self.root = pathlib.Path(root)
        self.lock = threading.Lock()

    def append(self, events):
        day = dt.date.today().isoformat()
        with self.lock:
            for event in events:
                session = "".join(c for c in str(event.get("session", "unknown")) if c.isalnum()) or "unknown"
                folder = self.root / day
                folder.mkdir(parents=True, exist_ok=True)
                with open(folder / f"{session}.jsonl", "a", encoding="utf-8") as handle:
                    handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def make_handler(store, quiet):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self._reply(200, b"ok")
            else:
                self._reply(404, b"not found")

        def do_POST(self):
            if self.path != "/logs":
                self._reply(404, b"not found")
                return
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            events = []
            for line in body.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    events.append({"level": "warn", "cat": "logserver", "msg": "unparsable line", "f": {"line": line[:200]}})
            store.append(events)
            if not quiet:
                for event in events:
                    print(summarize(event), flush=True)
            self._reply(200, b"ok")

        def _reply(self, status, body):
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    return Handler


def make_server(port, root, quiet=False):
    return ThreadingHTTPServer(("0.0.0.0", port), make_handler(LogStore(root), quiet))


def advertise(port):
    from zeroconf import ServiceInfo, Zeroconf

    zeroconf = Zeroconf()
    addresses = [socket.inet_aton(address) for address in lan_addresses()]
    name = f"BiliNative log on {socket.gethostname()}.{SERVICE_TYPE}"
    info = ServiceInfo(SERVICE_TYPE, name, addresses=addresses, port=port, properties={"path": "/logs"})
    zeroconf.register_service(info)
    return zeroconf, info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=47321)
    parser.add_argument("--no-bonjour", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    server = make_server(args.port, ROOT / "logs", args.quiet)
    print(f"Writing to {ROOT / 'logs'}")
    for address in lan_addresses():
        print(f"Phone: enter {address}:{args.port}")
    zeroconf = None
    if not args.no_bonjour:
        zeroconf, info = advertise(args.port)
        print("Advertised over Bonjour as", info.name)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if zeroconf:
            zeroconf.unregister_all_services()
            zeroconf.close()
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `python -m unittest discover -s tools -p "test_*.py" -v`
Expected: 3 tests OK.

- [ ] **Step 5: Smoke-test the real script with Bonjour**

Run in the background: `uv run tools/logserver.py`
Expected: prints `Writing to …\logs`, one `Phone: enter 192.168.x.y:47321` line and `Advertised over Bonjour as …`. Windows may show a firewall prompt: KaiC allows it for **private networks only**. Then post one line from another shell:

```bash
curl -s -X POST --data-binary '{"t":1,"seq":1,"session":"smoke","level":"info","cat":"app","msg":"hello","f":{}}' http://127.0.0.1:47321/logs
```

Expected: `ok`, a coloured line in the server output, and `logs/<today>/smoke.jsonl`. Stop the server and delete `logs/<today>/smoke.jsonl`.

- [ ] **Step 6: Commit**

```bash
git add tools/
git commit -m "Add PC log receiver with Bonjour advertising"
```

---
### Task 5: BiliAPI part 1, MD5 and WBI signing

**Files:**
- Modify: `Package.swift`
- Create: `Sources/BiliAPI/MD5.swift`, `Sources/BiliAPI/WBI.swift`
- Test: `Tests/BiliAPITests/WBITests.swift`

**Interfaces:**
- Produces: `MD5.hex(_ string: String) -> String`, `MD5.hex(_ bytes: [UInt8]) -> String`; `WBI.mixinKey(imgKey:subKey:) -> String`, `WBI.key(fromURL:) -> String`, `WBI.encodeComponent(_:) -> String`, `WBI.encodeQuery(_ params: [String: String]) -> String`, `WBI.signedQuery(_ params: [String: String], mixinKey: String, wts: Int) -> String` (sorted, encoded, ends with `&w_rid=<md5>`).

The reference values below were computed with Python's `hashlib` and the documented WBI algorithm; the first vector is the one published in the community API documentation.

- [ ] **Step 1: Register the module**

In `Package.swift` add `"BiliAPI"` to the product and to `targets:`:

```swift
        .target(name: "BiliAPI", dependencies: ["BiliShared", "DevLog"]),
        .testTarget(name: "BiliAPITests", dependencies: ["BiliAPI", "BiliShared", "DevLog"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/BiliAPITests/WBITests.swift`:

```swift
import XCTest
@testable import BiliAPI

final class WBITests: XCTestCase {
    func testMD5Vectors() {
        XCTAssertEqual(MD5.hex(""), "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(MD5.hex("a"), "0cc175b9c0f1b6a831c399e269772661")
        XCTAssertEqual(MD5.hex("abc"), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(MD5.hex("message digest"), "f96b697d7cb7938d525a2f31aaf161d0")
        XCTAssertEqual(MD5.hex("The quick brown fox jumps over the lazy dog"), "9e107d9d372bb6826bd81d3542a419d6")
        XCTAssertEqual(MD5.hex(String(repeating: "x", count: 1000)).count, 32)
    }

    func testMixinKey() {
        XCTAssertEqual(WBI.mixinKey(imgKey: "7cd084941338484aae1ad9425b84077c", subKey: "4932caff0ff746eab6f01bf08b70ac45"),
                       "ea1db124af3c7062474693fa704f4ff8")
    }

    func testKeyFromURL() {
        XCTAssertEqual(WBI.key(fromURL: "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png"),
                       "7cd084941338484aae1ad9425b84077c")
    }

    func testSignedQueryReferenceVector() {
        let query = WBI.signedQuery(["foo": "114", "bar": "514", "zab": "1919810"],
                                    mixinKey: "ea1db124af3c7062474693fa704f4ff8", wts: 1_702_204_169)
        XCTAssertEqual(query, "bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4")
    }

    func testSignedQueryFiltersAndEncodes() {
        let query = WBI.signedQuery(["keyword": "中文 a+b!(x)"], mixinKey: "ea1db124af3c7062474693fa704f4ff8", wts: 1_700_000_000)
        XCTAssertEqual(query, "keyword=%E4%B8%AD%E6%96%87%20a%2Bbx&wts=1700000000&w_rid=391f961efc403664b08d417a32bbba8b")
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter WBITests`
Expected: compile errors (`cannot find 'MD5' in scope`).

- [ ] **Step 4: Implement MD5**

Foundation on Windows has no CryptoKit, and WBI needs MD5 on both platforms, so it is implemented here (RFC 1321).

`Sources/BiliAPI/MD5.swift`:

```swift
enum MD5 {
    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    private static let constants: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]

    static func hex(_ string: String) -> String {
        hex(Array(string.utf8))
    }

    static func hex(_ bytes: [UInt8]) -> String {
        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        var message = bytes
        let bitLength = UInt64(bytes.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for index in 0..<8 { message.append(UInt8((bitLength >> (8 * UInt64(index))) & 0xff)) }

        var words = [UInt32](repeating: 0, count: 16)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let offset = chunk + index * 4
                words[index] = UInt32(message[offset])
                    | UInt32(message[offset + 1]) << 8
                    | UInt32(message[offset + 2]) << 16
                    | UInt32(message[offset + 3]) << 24
            }
            var a = a0, b = b0, c = c0, d = d0
            for round in 0..<64 {
                var f: UInt32
                let g: Int
                switch round {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = round
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 * round + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * round + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * round) % 16
                }
                f = f &+ a &+ constants[round] &+ words[g]
                a = d
                d = c
                c = b
                b = b &+ ((f << shifts[round]) | (f >> (32 - shifts[round])))
            }
            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
        }

        let digits = Array("0123456789abcdef")
        var output = ""
        for word in [a0, b0, c0, d0] {
            for index in 0..<4 {
                let byte = Int((word >> (8 * UInt32(index))) & 0xff)
                output.append(digits[byte >> 4])
                output.append(digits[byte & 0x0f])
            }
        }
        return output
    }
}
```

- [ ] **Step 5: Implement WBI**

`Sources/BiliAPI/WBI.swift`:

```swift
enum WBI {
    private static let table: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ]

    static func mixinKey(imgKey: String, subKey: String) -> String {
        let raw = Array(imgKey + subKey)
        return String(table.compactMap { $0 < raw.count ? raw[$0] : nil }.prefix(32))
    }

    /// The key is the file name of the image URL Bilibili hands out in `nav`, without extension.
    static func key(fromURL url: String) -> String {
        let file = url.split(separator: "/").last.map(String.init) ?? ""
        return file.split(separator: ".").first.map(String.init) ?? ""
    }

    /// encodeURIComponent semantics: everything except A-Z a-z 0-9 - . _ ~ is percent-encoded.
    static func encodeComponent(_ text: String) -> String {
        let hexDigits = Array("0123456789ABCDEF")
        var output = ""
        for byte in text.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E:
                output.append(Character(UnicodeScalar(byte)))
            default:
                output.append("%")
                output.append(hexDigits[Int(byte >> 4)])
                output.append(hexDigits[Int(byte & 0x0f)])
            }
        }
        return output
    }

    static func encodeQuery(_ params: [String: String]) -> String {
        params.keys.sorted().map { "\(encodeComponent($0))=\(encodeComponent(params[$0] ?? ""))" }.joined(separator: "&")
    }

    static func signedQuery(_ params: [String: String], mixinKey: String, wts: Int) -> String {
        var cleaned = params.mapValues { value in value.filter { !"!'()*".contains($0) } }
        cleaned["wts"] = String(wts)
        let query = encodeQuery(cleaned)
        return query + "&w_rid=" + MD5.hex(query + mixinKey)
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter WBITests`
Expected: 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add MD5 and WBI request signing"
```

---

### Task 6: BiliAPI part 2, link parser

**Files:**
- Create: `Sources/BiliAPI/LinkParser.swift`
- Test: `Tests/BiliAPITests/LinkParserTests.swift`

**Interfaces:**
- Produces: `enum VideoLink: Equatable, Sendable { case bvid(String, page: Int?), aid(Int64, page: Int?), short(URL) }` with `isShort`; `LinkParser.parse(_ text: String) -> VideoLink?`.

- [ ] **Step 1: Write the failing tests**

`Tests/BiliAPITests/LinkParserTests.swift`:

```swift
import XCTest
@testable import BiliAPI

final class LinkParserTests: XCTestCase {
    func testFullVideoURLWithPage() {
        XCTAssertEqual(LinkParser.parse("https://www.bilibili.com/video/BV1GJ411x7h7?p=2&spm_id_from=333.1007"),
                       .bvid("BV1GJ411x7h7", page: 2))
    }

    func testBareIDs() {
        XCTAssertEqual(LinkParser.parse("BV1GJ411x7h7"), .bvid("BV1GJ411x7h7", page: nil))
        XCTAssertEqual(LinkParser.parse("av170001"), .aid(170001, page: nil))
        XCTAssertEqual(LinkParser.parse("https://m.bilibili.com/video/av170001"), .aid(170001, page: nil))
    }

    func testTextSharedFromTheOfficialApp() {
        let shared = "【拥有NPC剧情、CG动画、GalGame的MC整合包『化龍』1.4正式版发布-哔哩哔哩】 https://b23.tv/xyZ123a 快来看看吧！"
        XCTAssertEqual(LinkParser.parse(shared), .short(URL(string: "https://b23.tv/xyZ123a")!))
        XCTAssertEqual(LinkParser.parse("看看这个 https://bili2233.cn/AbC9"), .short(URL(string: "https://bili2233.cn/AbC9")!))
        XCTAssertEqual(LinkParser.parse("  \nBV1GJ411x7h7\n "), .bvid("BV1GJ411x7h7", page: nil))
    }

    func testRejectsNonLinks() {
        XCTAssertNil(LinkParser.parse("hello"))
        XCTAssertNil(LinkParser.parse("BV1GJ411x7h"))
        XCTAssertNil(LinkParser.parse("travel tips"))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter LinkParserTests`
Expected: compile error (`cannot find 'LinkParser'`).

- [ ] **Step 3: Implement the parser**

`Sources/BiliAPI/LinkParser.swift`:

```swift
import Foundation

public enum VideoLink: Equatable, Sendable {
    case bvid(String, page: Int?)
    case aid(Int64, page: Int?)
    case short(URL)

    public var isShort: Bool {
        if case .short = self { return true }
        return false
    }
}

public enum LinkParser {
    private static let shortPattern = try! NSRegularExpression(pattern: #"https?://(?:b23\.tv|bili2233\.cn)/[A-Za-z0-9]+"#)
    private static let pagePattern = try! NSRegularExpression(pattern: #"[?&]p=(\d+)"#)
    private static let bvPattern = try! NSRegularExpression(pattern: #"BV1[0-9A-Za-z]{9}(?![0-9A-Za-z])"#)
    private static let avPattern = try! NSRegularExpression(pattern: #"(?i)(?:^|[^a-z0-9])av(\d+)"#)

    /// Finds a video in anything a user might paste: a URL, a bare id, or the share text of the official app.
    public static func parse(_ text: String) -> VideoLink? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = first(shortPattern, in: input), let url = URL(string: match) {
            return .short(url)
        }
        let page = first(pagePattern, group: 1, in: input).flatMap { Int($0) }
        if let bv = first(bvPattern, in: input) {
            return .bvid(bv, page: page)
        }
        if let av = first(avPattern, group: 1, in: input), let id = Int64(av) {
            return .aid(id, page: page)
        }
        return nil
    }

    private static func first(_ regex: NSRegularExpression, group: Int = 0, in text: String) -> String? {
        let ns = NSString(string: text)
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter LinkParserTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add video link parser"
```

---

### Task 7: BiliAPI part 3, response models and track selection

**Files:**
- Create: `Sources/BiliAPI/Models.swift`, `Sources/BiliAPI/TrackSelector.swift`
- Test: `Tests/BiliAPITests/Fixtures.swift`, `Tests/BiliAPITests/ModelsTests.swift`, `Tests/BiliAPITests/TrackSelectorTests.swift`

**Interfaces:**
- Consumes: `ByteRange` (BiliShared).
- Produces:
  - `BiliEnvelope<T>` (`code`, `message`, `data`).
  - `NavInfo` (`isLogin`, `mid`, `uname`, `vipStatus`, `vipType`, `imgURL`, `subURL`, `isVip`).
  - `VideoPage` (`cid`, `page`, `part`, `duration`), `VideoView` (`bvid`, `aid`, `title`, `owner`, `pages`).
  - `DashStream(id:baseURL:backupURLs:bandwidth:mimeType:codecs:codecid:width:height:frameRate:initialization:indexRange:)`, `Dash(duration:video:audio:)`, `PlayURLInfo(quality:acceptQuality:acceptDescription:dash:hasDurl:)`, `QualityOption` (`id`, `name`), `PlayURLInfo.qualityOptions`, `SPIInfo` (`b3`, `b4`).
  - `VideoCodec` (`hevc`, `av1`, `avc`; `codecid`, `label`), `TrackChoice` (`video`, `audio`), `TrackSelector.choose(_:quality:codecOrder:excludeDolbyVision:)`, `TrackSelector.bestAudio(_:)`, `TrackSelector.codecKind(_:) -> String` (`"dolby"`, `"hevc"`, `"av1"`, `"avc"`, `"other"`).

- [ ] **Step 1: Add the fixtures**

These are shaped like real responses, including both spellings Bilibili uses for the same fields.

`Tests/BiliAPITests/Fixtures.swift`:

```swift
enum Fixtures {
    static let navLoggedOut = #"""
    {"code":-101,"message":"账号未登录","ttl":1,"data":{"isLogin":false,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}
    """#

    static let navLoggedIn = #"""
    {"code":0,"message":"0","ttl":1,"data":{"isLogin":true,"mid":12345,"uname":"测试用户","vipStatus":1,"vipType":2,"wbi_img":{"img_url":"https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png","sub_url":"https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png"}}}
    """#

    static let view = #"""
    {"code":0,"message":"0","ttl":1,"data":{"bvid":"BV1GJ411x7h7","aid":80433022,"title":"测试视频","owner":{"mid":1,"name":"UP主"},"pages":[{"cid":137649199,"page":1,"part":"第一集","duration":212},{"cid":137649200,"page":2,"part":"第二集","duration":100}]}}
    """#

    static let spi = #"""
    {"code":0,"message":"ok","data":{"b_3":"B3-VALUE-infoc","b_4":"B4-VALUE"}}
    """#

    static let notFound = #"""
    {"code":-404,"message":"啥都木有","ttl":1}
    """#

    static let playURL = #"""
    {"code":0,"message":"0","ttl":1,"data":{"quality":120,"format":"hdflv2","accept_quality":[127,126,125,120,116,80,64,32,16],"accept_description":["超高清 8K","杜比视界","真彩 HDR","超清 4K","高清 1080P60","高清 1080P","高清 720P","清晰 480P","流畅 360P"],
    "dash":{"duration":214,"minBufferTime":1.5,
    "video":[
    {"id":120,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv","base_url":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv","backupUrl":["https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=alibv"],"backup_url":["https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=alibv"],"bandwidth":12000000,"mimeType":"video/mp4","mime_type":"video/mp4","codecs":"hev1.1.6.L153.90","width":3840,"height":2160,"frameRate":"29.412","frame_rate":"29.412","SegmentBase":{"Initialization":"0-1104","indexRange":"1105-1688"},"segment_base":{"initialization":"0-1104","index_range":"1105-1688"},"codecid":12},
    {"id":120,"base_url":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100048.m4s?deadline=1760000000","backup_url":null,"bandwidth":15000000,"mime_type":"video/mp4","codecs":"avc1.640034","width":3840,"height":2160,"segment_base":{"initialization":"0-1000","index_range":"1001-1600"},"codecid":7},
    {"id":80,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100113.m4s?deadline=1760000000","backupUrl":[],"bandwidth":2000000,"mimeType":"video/mp4","codecs":"av01.0.08M.08.0.110.01.01.01.0","width":1920,"height":1080,"frameRate":"29.412","SegmentBase":{"Initialization":"0-900","indexRange":"901-1500"},"codecid":13},
    {"id":126,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100126.m4s?deadline=1760000000","backupUrl":null,"bandwidth":20000000,"mimeType":"video/mp4","codecs":"dvh1.08.07","width":3840,"height":2160,"frameRate":"29.412","SegmentBase":{"Initialization":"0-1200","indexRange":"1201-1800"},"codecid":12}
    ],
    "audio":[
    {"id":30216,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-30216.m4s?deadline=1760000000","backupUrl":null,"bandwidth":67000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","width":0,"height":0,"frameRate":"","SegmentBase":{"Initialization":"0-907","indexRange":"908-1491"},"codecid":0},
    {"id":30280,"baseUrl":"https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-30280.m4s?deadline=1760000000","backupUrl":null,"bandwidth":320000,"mimeType":"audio/mp4","codecs":"mp4a.40.2","width":0,"height":0,"frameRate":"","SegmentBase":{"Initialization":"0-907","indexRange":"908-1491"},"codecid":0}
    ],
    "dolby":{"type":0,"audio":null},"flac":null}}}
    """#

    static let durlOnly = #"""
    {"code":0,"message":"0","ttl":1,"data":{"quality":64,"accept_quality":[64,32],"accept_description":["高清 720P","清晰 480P"],"durl":[{"order":1,"length":120000,"size":1000,"url":"https://upos-sz-mirrorcos.bilivideo.com/a.flv"}]}}
    """#
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/BiliAPITests/ModelsTests.swift`:

```swift
import XCTest
import BiliShared
@testable import BiliAPI

final class ModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> BiliEnvelope<T> {
        try JSONDecoder().decode(BiliEnvelope<T>.self, from: Data(json.utf8))
    }

    func testNavLoggedOutStillCarriesWBIKeys() throws {
        let envelope = try decode(NavInfo.self, Fixtures.navLoggedOut)
        XCTAssertEqual(envelope.code, -101)
        XCTAssertEqual(envelope.data?.isLogin, false)
        XCTAssertEqual(envelope.data?.imgURL, "https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png")
    }

    func testNavLoggedIn() throws {
        let nav = try XCTUnwrap(decode(NavInfo.self, Fixtures.navLoggedIn).data)
        XCTAssertTrue(nav.isLogin)
        XCTAssertTrue(nav.isVip)
        XCTAssertEqual(nav.mid, 12345)
        XCTAssertEqual(nav.uname, "测试用户")
    }

    func testView() throws {
        let view = try XCTUnwrap(decode(VideoView.self, Fixtures.view).data)
        XCTAssertEqual(view.bvid, "BV1GJ411x7h7")
        XCTAssertEqual(view.owner, "UP主")
        XCTAssertEqual(view.pages.map(\.cid), [137649199, 137649200])
        XCTAssertEqual(view.pages[1].part, "第二集")
    }

    func testErrorEnvelopeWithoutData() throws {
        let envelope = try decode(VideoView.self, Fixtures.notFound)
        XCTAssertEqual(envelope.code, -404)
        XCTAssertNil(envelope.data)
    }

    func testPlayURLFieldSpellings() throws {
        let info = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.playURL).data)
        let dash = try XCTUnwrap(info.dash)
        XCTAssertEqual(dash.duration, 214)
        XCTAssertEqual(dash.video.count, 4)
        let hevc = dash.video[0]
        XCTAssertEqual(hevc.baseURL, "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/3-1-100151.m4s?deadline=1760000000&os=cosbv")
        XCTAssertEqual(hevc.backupURLs.count, 1)
        XCTAssertEqual(hevc.initialization, ByteRange(start: 0, end: 1104))
        XCTAssertEqual(hevc.indexRange, ByteRange(start: 1105, end: 1688))
        XCTAssertEqual(hevc.frameRate, "29.412")
        let snake = dash.video[1]
        XCTAssertEqual(snake.backupURLs, [])
        XCTAssertNil(snake.frameRate)
        XCTAssertEqual(snake.indexRange, ByteRange(start: 1001, end: 1600))
        XCTAssertEqual(dash.audio.map(\.id), [30216, 30280])
        XCTAssertFalse(info.hasDurl)
        XCTAssertEqual(info.qualityOptions.first, QualityOption(id: 127, name: "超高清 8K"))
    }

    func testDurlOnlyHasNoDash() throws {
        let info = try XCTUnwrap(decode(PlayURLInfo.self, Fixtures.durlOnly).data)
        XCTAssertNil(info.dash)
        XCTAssertTrue(info.hasDurl)
    }
}
```

`Tests/BiliAPITests/TrackSelectorTests.swift`:

```swift
import XCTest
@testable import BiliAPI

final class TrackSelectorTests: XCTestCase {
    private var dash: Dash!

    override func setUpWithError() throws {
        let envelope = try JSONDecoder().decode(BiliEnvelope<PlayURLInfo>.self, from: Data(Fixtures.playURL.utf8))
        dash = try XCTUnwrap(envelope.data?.dash)
    }

    func testPrefersRequestedCodecAtRequestedQuality() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 120, codecOrder: [.hevc, .avc])?.video.codecs, "hev1.1.6.L153.90")
        XCTAssertEqual(TrackSelector.choose(dash, quality: 120, codecOrder: [.avc])?.video.codecs, "avc1.640034")
    }

    func testFallsToNextLowerQualityAndAnyCodec() {
        let choice = TrackSelector.choose(dash, quality: 116, codecOrder: [.hevc])
        XCTAssertEqual(choice?.video.id, 80)
        XCTAssertEqual(choice?.video.codecid, 13)
    }

    func testDolbyVisionCanBeExcluded() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 127, codecOrder: [.hevc])?.video.id, 126)
        XCTAssertEqual(TrackSelector.choose(dash, quality: 127, codecOrder: [.hevc], excludeDolbyVision: true)?.video.id, 120)
    }

    func testQualityBelowEverythingPicksLowest() {
        XCTAssertEqual(TrackSelector.choose(dash, quality: 16, codecOrder: [.hevc])?.video.id, 80)
    }

    func testBestAudioAndKinds() {
        XCTAssertEqual(TrackSelector.bestAudio(dash.audio)?.id, 30280)
        XCTAssertEqual(TrackSelector.codecKind(dash.video[3]), "dolby")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[0]), "hevc")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[2]), "av1")
        XCTAssertEqual(TrackSelector.codecKind(dash.video[1]), "avc")
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter "ModelsTests|TrackSelectorTests"`
Expected: compile errors.

- [ ] **Step 4: Implement the models**

`Sources/BiliAPI/Models.swift`:

```swift
import Foundation
import BiliShared

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where K == AnyKey {
    /// Bilibili spells many fields two ways (baseUrl/base_url); the first present, non-null one wins.
    func first<T: Decodable>(_ type: T.Type, _ keys: String...) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(T.self, forKey: AnyKey(key)) { return value }
        }
        return nil
    }

    func nested(_ keys: String...) -> KeyedDecodingContainer<AnyKey>? {
        for key in keys where contains(AnyKey(key)) {
            if let container = try? nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key)) { return container }
        }
        return nil
    }
}

private func missing(_ field: String, _ decoder: Decoder) -> DecodingError {
    DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "missing \(field)"))
}

public struct BiliEnvelope<T: Decodable>: Decodable {
    public let code: Int
    public let message: String?
    public let data: T?

    enum CodingKeys: String, CodingKey { case code, message, data }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        // Error replies carry data of another shape, or none; only a success must decode strictly.
        if code == 0 {
            data = try container.decodeIfPresent(T.self, forKey: .data)
        } else {
            data = try? container.decodeIfPresent(T.self, forKey: .data)
        }
    }
}

public struct NavInfo: Decodable, Sendable, Equatable {
    public let isLogin: Bool
    public let mid: Int64?
    public let uname: String?
    public let vipStatus: Int
    public let vipType: Int
    public let imgURL: String
    public let subURL: String

    public var isVip: Bool { vipStatus == 1 }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        isLogin = try container.first(Bool.self, "isLogin") ?? false
        mid = try container.first(Int64.self, "mid")
        uname = try container.first(String.self, "uname")
        vipStatus = try container.first(Int.self, "vipStatus") ?? 0
        vipType = try container.first(Int.self, "vipType") ?? 0
        let images = container.nested("wbi_img")
        imgURL = try images?.first(String.self, "img_url") ?? ""
        subURL = try images?.first(String.self, "sub_url") ?? ""
    }
}

public struct SPIInfo: Decodable, Sendable {
    public let b3: String
    public let b4: String

    enum CodingKeys: String, CodingKey {
        case b3 = "b_3"
        case b4 = "b_4"
    }
}

public struct VideoPage: Decodable, Sendable, Hashable {
    public let cid: Int64
    public let page: Int
    public let part: String
    public let duration: Int

    public init(cid: Int64, page: Int, part: String, duration: Int) {
        self.cid = cid
        self.page = page
        self.part = part
        self.duration = duration
    }
}

public struct VideoView: Decodable, Sendable, Equatable {
    public let bvid: String
    public let aid: Int64
    public let title: String
    public let owner: String?
    public let pages: [VideoPage]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let bvid = try container.first(String.self, "bvid") else { throw missing("bvid", decoder) }
        self.bvid = bvid
        aid = try container.first(Int64.self, "aid") ?? 0
        title = try container.first(String.self, "title") ?? ""
        owner = try container.nested("owner")?.first(String.self, "name")
        pages = try container.first([VideoPage].self, "pages") ?? []
    }
}

public struct DashStream: Decodable, Sendable, Equatable {
    public let id: Int
    public let baseURL: String
    public let backupURLs: [String]
    public let bandwidth: Int
    public let mimeType: String
    public let codecs: String
    public let codecid: Int
    public let width: Int
    public let height: Int
    public let frameRate: String?
    public let initialization: ByteRange
    public let indexRange: ByteRange

    public init(id: Int, baseURL: String, backupURLs: [String], bandwidth: Int, mimeType: String, codecs: String, codecid: Int,
                width: Int, height: Int, frameRate: String?, initialization: ByteRange, indexRange: ByteRange) {
        self.id = id
        self.baseURL = baseURL
        self.backupURLs = backupURLs
        self.bandwidth = bandwidth
        self.mimeType = mimeType
        self.codecs = codecs
        self.codecid = codecid
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.initialization = initialization
        self.indexRange = indexRange
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        id = try container.first(Int.self, "id") ?? 0
        guard let base = try container.first(String.self, "baseUrl", "base_url") else { throw missing("baseUrl", decoder) }
        baseURL = base
        backupURLs = try container.first([String].self, "backupUrl", "backup_url") ?? []
        bandwidth = try container.first(Int.self, "bandwidth") ?? 0
        mimeType = try container.first(String.self, "mimeType", "mime_type") ?? ""
        codecs = try container.first(String.self, "codecs") ?? ""
        codecid = try container.first(Int.self, "codecid") ?? 0
        width = try container.first(Int.self, "width") ?? 0
        height = try container.first(Int.self, "height") ?? 0
        let rate = try container.first(String.self, "frameRate", "frame_rate")
        frameRate = (rate?.isEmpty ?? true) ? nil : rate
        let initText: String?
        let indexText: String?
        if let segmentBase = container.nested("SegmentBase") {
            initText = try segmentBase.first(String.self, "Initialization", "initialization")
            indexText = try segmentBase.first(String.self, "indexRange", "index_range")
        } else if let segmentBase = container.nested("segment_base") {
            initText = try segmentBase.first(String.self, "initialization", "Initialization")
            indexText = try segmentBase.first(String.self, "index_range", "indexRange")
        } else {
            initText = nil
            indexText = nil
        }
        guard let initRange = initText.flatMap(ByteRange.parse), let index = indexText.flatMap(ByteRange.parse) else {
            throw missing("SegmentBase", decoder)
        }
        initialization = initRange
        indexRange = index
    }
}

public struct Dash: Decodable, Sendable, Equatable {
    public let duration: Int
    public let video: [DashStream]
    public let audio: [DashStream]

    public init(duration: Int, video: [DashStream], audio: [DashStream]) {
        self.duration = duration
        self.video = video
        self.audio = audio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        duration = try container.first(Int.self, "duration") ?? 0
        video = try container.first([DashStream].self, "video") ?? []
        audio = try container.first([DashStream].self, "audio") ?? []
    }
}

public struct QualityOption: Hashable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PlayURLInfo: Decodable, Sendable {
    public let quality: Int
    public let acceptQuality: [Int]
    public let acceptDescription: [String]
    public let dash: Dash?
    public let hasDurl: Bool

    public init(quality: Int, acceptQuality: [Int], acceptDescription: [String], dash: Dash?, hasDurl: Bool) {
        self.quality = quality
        self.acceptQuality = acceptQuality
        self.acceptDescription = acceptDescription
        self.dash = dash
        self.hasDurl = hasDurl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        quality = try container.first(Int.self, "quality") ?? 0
        acceptQuality = try container.first([Int].self, "accept_quality") ?? []
        acceptDescription = try container.first([String].self, "accept_description") ?? []
        dash = try container.first(Dash.self, "dash")
        hasDurl = container.contains(AnyKey("durl"))
    }

    public var qualityOptions: [QualityOption] {
        zip(acceptQuality, acceptDescription).map { QualityOption(id: $0.0, name: $0.1) }
    }
}
```

- [ ] **Step 5: Implement track selection**

`Sources/BiliAPI/TrackSelector.swift`:

```swift
public enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case hevc, av1, avc

    public var codecid: Int {
        switch self {
        case .hevc: return 12
        case .av1: return 13
        case .avc: return 7
        }
    }

    public var label: String {
        switch self {
        case .hevc: return "HEVC"
        case .av1: return "AV1"
        case .avc: return "H.264"
        }
    }
}

public struct TrackChoice: Sendable, Equatable {
    public let video: DashStream
    public let audio: DashStream

    public init(video: DashStream, audio: DashStream) {
        self.video = video
        self.audio = audio
    }
}

public enum TrackSelector {
    /// The highest quality not above `quality` (or the lowest offered), then the first codec of
    /// `codecOrder` that quality has, else whatever it has.
    public static func choose(_ dash: Dash, quality: Int, codecOrder: [VideoCodec], excludeDolbyVision: Bool = false) -> TrackChoice? {
        guard let audio = bestAudio(dash.audio) else { return nil }
        var videos = dash.video
        if excludeDolbyVision {
            videos.removeAll { codecKind($0) == "dolby" }
        }
        let qualities = Set(videos.map(\.id)).sorted(by: >)
        guard let picked = qualities.first(where: { $0 <= quality }) ?? qualities.last else { return nil }
        let candidates = videos.filter { $0.id == picked }
        for codec in codecOrder {
            if let video = candidates.first(where: { $0.codecid == codec.codecid }) {
                return TrackChoice(video: video, audio: audio)
            }
        }
        return candidates.first.map { TrackChoice(video: $0, audio: audio) }
    }

    /// AAC only: 30280 (192K) > 30232 (132K) > 30216 (64K). Dolby and Hi-Res are later milestones.
    public static func bestAudio(_ audio: [DashStream]) -> DashStream? {
        let rank = [30280: 3, 30232: 2, 30216: 1]
        return audio
            .filter { $0.codecs.hasPrefix("mp4a") }
            .max { (rank[$0.id] ?? 0, $0.bandwidth) < (rank[$1.id] ?? 0, $1.bandwidth) }
    }

    public static func codecKind(_ stream: DashStream) -> String {
        if stream.codecs.hasPrefix("dvh1") || stream.codecs.hasPrefix("dvhe") || stream.id == 126 { return "dolby" }
        switch stream.codecid {
        case 12: return "hevc"
        case 13: return "av1"
        case 7: return "avc"
        default: return "other"
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter "ModelsTests|TrackSelectorTests"`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Bilibili response models and track selection"
```

---

### Task 8: BiliAPI part 4, HTTP transport, cookie jar and client

**Files:**
- Create: `Sources/BiliAPI/HTTP.swift`, `Sources/BiliAPI/CookieJar.swift`, `Sources/BiliAPI/BiliError.swift`, `Sources/BiliAPI/BiliClient.swift`
- Test: `Tests/BiliAPITests/BiliClientTests.swift`

**Interfaces:**
- Consumes: `WBI`, `LinkParser`, models (Tasks 5-7); `Logger` (DevLog); `Locked` (BiliShared).
- Produces:
  - `HTTPRequest(url:headers:)`, `HTTPResponse(status:headers:body:finalURL:)` (header names lowercased), `protocol HTTPTransport: Sendable { func send(_:) async throws -> HTTPResponse }`, `URLSessionHTTPTransport()`.
  - `CookieJar(_:)` with `all`, `value(_:)`, `set(_:_:)`, `remove(_:)`, `replaceAll(_:)`, `removeAll()`, `headerValue`, `onChange`, `static parse(header:)`.
  - `BiliError` (`http(Int)`, `api(code:message:)`, `decoding(String)`, `notDash`, `invalidLink`) with `userMessage`.
  - `BiliClient(transport:cookies:now:logger:)` with `userAgent`, `referer`, `mediaHeaders`, `nav()`, `ensureRiskCookies()`, `view(bvid:)`, `view(aid:)`, `resolve(_:) -> (view: VideoView, page: Int?)`, `playURL(bvid:cid:quality:) -> PlayURLInfo` (throws `.notDash` without DASH). An HTTP 412 (risk control) is retried once with fresh `buvid3`/`buvid4`.

- [ ] **Step 1: Write the failing tests**

`Tests/BiliAPITests/BiliClientTests.swift`:

```swift
import XCTest
import BiliShared
import DevLog
@testable import BiliAPI

final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    var routes: [String: (Int, String)] = [:]
    var redirects: [String: URL] = [:]
    let requests = Locked<[HTTPRequest]>([])

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.withLock { $0.append(request) }
        let key = (request.url.host ?? "") + request.url.path
        if let final = redirects[key] {
            return HTTPResponse(status: 200, headers: [:], body: Data(), finalURL: final)
        }
        guard let (status, body) = routes[request.url.path] else {
            return HTTPResponse(status: 404, headers: [:], body: Data(), finalURL: request.url)
        }
        return HTTPResponse(status: status, headers: [:], body: Data(body.utf8), finalURL: request.url)
    }

    func requests(to path: String) -> [HTTPRequest] {
        requests.current.filter { $0.url.path == path }
    }

    func query(of request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

final class BiliClientTests: XCTestCase {
    private let navPath = "/x/web-interface/nav"
    private let viewPath = "/x/web-interface/view"
    private let playPath = "/x/player/wbi/playurl"
    private let spiPath = "/x/frontend/finger/spi"

    private func makeClient(_ http: FakeHTTP, cookies: [String: String] = [:]) -> BiliClient {
        BiliClient(transport: http, cookies: CookieJar(cookies),
                   now: { Date(timeIntervalSince1970: 1_702_204_169) }, logger: Logger(session: "test"))
    }

    func testNavDecodesLoggedOutAndKeysAreCachedForSigning() async throws {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedOut), playPath: (200, Fixtures.playURL)]
        let client = makeClient(http)
        let nav = try await client.nav()
        XCTAssertFalse(nav.isLogin)
        _ = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 120)
        _ = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 120)
        XCTAssertEqual(http.requests(to: navPath).count, 1)
    }

    func testPlayURLSendsDashFlagsSignatureAndHeaders() async throws {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.playURL)]
        let client = makeClient(http, cookies: ["SESSDATA": "abc", "buvid3": "b3"])
        let info = try await client.playURL(bvid: "BV1GJ411x7h7", cid: 137649199, quality: 120)
        XCTAssertEqual(info.dash?.video.count, 4)
        let request = try XCTUnwrap(http.requests(to: playPath).first)
        let query = http.query(of: request)
        XCTAssertEqual(query["fnval"], "4048")
        XCTAssertEqual(query["fourk"], "1")
        XCTAssertEqual(query["qn"], "120")
        XCTAssertEqual(query["wts"], "1702204169")
        XCTAssertEqual(query["w_rid"]?.count, 32)
        XCTAssertEqual(request.headers["Referer"], "https://www.bilibili.com/")
        XCTAssertEqual(request.headers["User-Agent"], BiliClient.userAgent)
        XCTAssertEqual(request.headers["Cookie"], "SESSDATA=abc; buvid3=b3")
    }

    func testEnsureRiskCookiesFetchesOnlyWhenMissing() async throws {
        let http = FakeHTTP()
        http.routes = [spiPath: (200, Fixtures.spi)]
        let client = makeClient(http)
        try await client.ensureRiskCookies()
        XCTAssertEqual(client.cookies.value("buvid3"), "B3-VALUE-infoc")
        XCTAssertEqual(client.cookies.value("buvid4"), "B4-VALUE")
        try await client.ensureRiskCookies()
        XCTAssertEqual(http.requests(to: spiPath).count, 1)
    }

    func testAPIErrorCodeThrows() async {
        let http = FakeHTTP()
        http.routes = [viewPath: (200, Fixtures.notFound)]
        do {
            _ = try await makeClient(http).view(bvid: "BV1GJ411x7h7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .api(code: -404, message: "啥都木有"))
            XCTAssertEqual((error as? BiliError)?.userMessage, "视频不存在或已被删除")
        }
    }

    func testDurlOnlyThrowsNotDash() async {
        let http = FakeHTTP()
        http.routes = [navPath: (200, Fixtures.navLoggedIn), playPath: (200, Fixtures.durlOnly)]
        do {
            _ = try await makeClient(http).playURL(bvid: "BV1GJ411x7h7", cid: 1, quality: 80)
            XCTFail("expected notDash")
        } catch {
            XCTAssertEqual(error as? BiliError, .notDash)
            XCTAssertEqual((error as? BiliError)?.userMessage, "这个视频不是 DASH 格式，暂不支持")
        }
    }

    func testRiskControlIsRetriedOnceWithFreshCookies() async {
        let http = FakeHTTP()
        http.routes = [viewPath: (412, ""), spiPath: (200, Fixtures.spi)]
        let client = makeClient(http, cookies: ["buvid3": "old", "buvid4": "old"])
        do {
            _ = try await client.view(bvid: "BV1GJ411x7h7")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BiliError, .http(412))
        }
        XCTAssertEqual(http.requests(to: viewPath).count, 2)
        XCTAssertEqual(http.requests(to: spiPath).count, 1)
        XCTAssertEqual(client.cookies.value("buvid3"), "B3-VALUE-infoc")
    }

    func testResolveShortLinkFollowsRedirect() async throws {
        let http = FakeHTTP()
        http.routes = [viewPath: (200, Fixtures.view)]
        http.redirects["b23.tv/xyZ123a"] = URL(string: "https://www.bilibili.com/video/BV1GJ411x7h7?p=2&share_source=copy")!
        let (view, page) = try await makeClient(http).resolve(.short(URL(string: "https://b23.tv/xyZ123a")!))
        XCTAssertEqual(view.bvid, "BV1GJ411x7h7")
        XCTAssertEqual(page, 2)
        XCTAssertEqual(http.query(of: try XCTUnwrap(http.requests(to: viewPath).first))["bvid"], "BV1GJ411x7h7")
    }

    func testCookieJarHeaderAndParse() {
        let jar = CookieJar(CookieJar.parse(header: "SESSDATA=abc; buvid3=x=y; empty"))
        XCTAssertEqual(jar.value("buvid3"), "x=y")
        XCTAssertEqual(jar.headerValue, "SESSDATA=abc; buvid3=x=y")
        let changes = Locked(0)
        jar.onChange = { _ in changes.withLock { $0 += 1 } }
        jar.set("bili_jct", "z")
        jar.removeAll()
        XCTAssertEqual(changes.current, 2)
        XCTAssertNil(jar.headerValue)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter BiliClientTests`
Expected: compile errors.

- [ ] **Step 3: Implement HTTP, cookies and errors**

`Sources/BiliAPI/HTTP.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Sendable {
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    /// Lowercased header names.
    public var headers: [String: String]
    public var body: Data
    /// After redirects, which is how b23.tv short links are resolved.
    public var finalURL: URL

    public init(status: Int, headers: [String: String], body: Data, finalURL: URL) {
        self.status = status
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        // Cookies are managed by CookieJar; URLSession's own store would send stale ones.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: BiliError.http(0))
                    return
                }
                var headers: [String: String] = [:]
                for (name, value) in http.allHeaderFields {
                    if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
                }
                continuation.resume(returning: HTTPResponse(status: http.statusCode, headers: headers, body: data ?? Data(),
                                                            finalURL: http.url ?? request.url))
            }.resume()
        }
    }
}
```

`Sources/BiliAPI/CookieJar.swift`:

```swift
import Foundation
import BiliShared

public final class CookieJar: @unchecked Sendable {
    private let state: Locked<[String: String]>
    /// Called with the full jar after every change (the app persists it to the Keychain).
    public var onChange: (@Sendable ([String: String]) -> Void)?

    public init(_ cookies: [String: String] = [:]) {
        state = Locked(cookies)
    }

    public var all: [String: String] { state.current }

    public func value(_ name: String) -> String? {
        state.current[name]
    }

    public func set(_ name: String, _ value: String) {
        let snapshot = state.withLock { cookies -> [String: String] in
            cookies[name] = value
            return cookies
        }
        onChange?(snapshot)
    }

    public func remove(_ name: String) {
        let snapshot = state.withLock { cookies -> [String: String] in
            cookies[name] = nil
            return cookies
        }
        onChange?(snapshot)
    }

    public func replaceAll(_ cookies: [String: String]) {
        state.withLock { $0 = cookies }
        onChange?(cookies)
    }

    public func removeAll() {
        state.withLock { $0 = [:] }
        onChange?([:])
    }

    public var headerValue: String? {
        let cookies = state.current
        guard !cookies.isEmpty else { return nil }
        func rank(_ name: String) -> Int { name.lowercased() == "sessdata" ? 0 : 1 }
        return cookies.keys.sorted { (rank($0), $0) < (rank($1), $1) }
            .map { "\($0)=\(cookies[$0] ?? "")" }
            .joined(separator: "; ")
    }

    public static func parse(header: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { result[name] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return result
    }
}
```

(`headerValue` puts `SESSDATA` first and the rest alphabetically, so tests and logs see a stable order.)

`Sources/BiliAPI/BiliError.swift`:

```swift
public enum BiliError: Error, Equatable, Sendable {
    case http(Int)
    case api(code: Int, message: String)
    case decoding(String)
    case notDash
    case invalidLink

    public var userMessage: String {
        switch self {
        case .http(412):
            return "B 站暂时拒绝了请求（风控），稍后再试"
        case .http(let status):
            return "网络请求失败（HTTP \(status)）"
        case .api(-101, _):
            return "需要登录"
        case .api(-404, _), .api(62002, _), .api(62004, _):
            return "视频不存在或已被删除"
        case .api(let code, let message):
            return "B 站返回错误 \(code)：\(message)"
        case .decoding:
            return "B 站返回的数据无法解析"
        case .notDash:
            return "这个视频不是 DASH 格式，暂不支持"
        case .invalidLink:
            return "没有找到视频链接"
        }
    }
}
```

- [ ] **Step 4: Implement the client**

`Sources/BiliAPI/BiliClient.swift`:

```swift
import Foundation
import BiliShared
import DevLog

public final class BiliClient: @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    public static let referer = "https://www.bilibili.com/"
    public static var mediaHeaders: [String: String] { ["User-Agent": userAgent, "Referer": referer] }
    /// DASH | HDR | 4K | Dolby audio | Dolby Vision | 8K | AV1.
    public static let dashFnval = 4048

    private static let api = "https://api.bilibili.com"

    private let transport: HTTPTransport
    public let cookies: CookieJar
    private let now: @Sendable () -> Date
    private let logger: Logger
    private let wbiCache = Locked<(day: String, mixin: String)?>(nil)

    public init(transport: HTTPTransport, cookies: CookieJar, now: @escaping @Sendable () -> Date = { Date() }, logger: Logger = .shared) {
        self.transport = transport
        self.cookies = cookies
        self.now = now
        self.logger = logger
    }

    /// A logged-out reply (-101) still carries the WBI keys, so it is returned, not thrown.
    public func nav() async throws -> NavInfo {
        let envelope: BiliEnvelope<NavInfo> = try await get("/x/web-interface/nav", query: [:], signed: false)
        guard let nav = envelope.data else {
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
        let mixin = WBI.mixinKey(imgKey: WBI.key(fromURL: nav.imgURL), subKey: WBI.key(fromURL: nav.subURL))
        if mixin.count == 32 { wbiCache.withLock { $0 = (today(), mixin) } }
        return nav
    }

    /// The web API answers 412 to requests without the website's fingerprint cookies.
    public func ensureRiskCookies() async throws {
        guard cookies.value("buvid3") == nil || cookies.value("buvid4") == nil else { return }
        let envelope: BiliEnvelope<SPIInfo> = try await get("/x/frontend/finger/spi", query: [:], signed: false)
        let spi = try checked(envelope)
        if cookies.value("buvid3") == nil { cookies.set("buvid3", spi.b3) }
        if cookies.value("buvid4") == nil { cookies.set("buvid4", spi.b4) }
    }

    public func view(bvid: String) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await get("/x/web-interface/view", query: ["bvid": bvid], signed: false)
        return try checked(envelope)
    }

    public func view(aid: Int64) async throws -> VideoView {
        let envelope: BiliEnvelope<VideoView> = try await get("/x/web-interface/view", query: ["aid": String(aid)], signed: false)
        return try checked(envelope)
    }

    public func resolve(_ link: VideoLink) async throws -> (view: VideoView, page: Int?) {
        switch link {
        case .bvid(let id, let page):
            return (try await view(bvid: id), page)
        case .aid(let id, let page):
            return (try await view(aid: id), page)
        case .short(let url):
            let response = try await transport.send(HTTPRequest(url: url, headers: ["User-Agent": Self.userAgent]))
            guard let next = LinkParser.parse(response.finalURL.absoluteString), !next.isShort else {
                throw BiliError.invalidLink
            }
            return try await resolve(next)
        }
    }

    public func playURL(bvid: String, cid: Int64, quality: Int) async throws -> PlayURLInfo {
        let query = ["bvid": bvid, "cid": String(cid), "qn": String(quality), "fnval": String(Self.dashFnval), "fnver": "0", "fourk": "1"]
        let envelope: BiliEnvelope<PlayURLInfo> = try await get("/x/player/wbi/playurl", query: query, signed: true)
        let info = try checked(envelope)
        guard info.dash != nil else { throw BiliError.notDash }
        return info
    }

    private func mixinKey() async throws -> String {
        if let cached = wbiCache.current, cached.day == today() { return cached.mixin }
        _ = try await nav()
        guard let cached = wbiCache.current else { throw BiliError.decoding("WBI keys missing from nav") }
        return cached.mixin
    }

    private func today() -> String {
        let seconds = Int(now().timeIntervalSince1970)
        return String(seconds / 86_400)
    }

    private func checked<T>(_ envelope: BiliEnvelope<T>) throws -> T {
        guard envelope.code == 0, let data = envelope.data else {
            throw BiliError.api(code: envelope.code, message: envelope.message ?? "")
        }
        return data
    }

    private func get<T: Decodable>(_ path: String, query: [String: String], signed: Bool, retried: Bool = false) async throws -> BiliEnvelope<T> {
        let queryString: String
        if signed {
            let key = try await mixinKey()
            queryString = WBI.signedQuery(query, mixinKey: key, wts: Int(now().timeIntervalSince1970))
        } else {
            queryString = WBI.encodeQuery(query)
        }
        guard let url = URL(string: Self.api + path + (queryString.isEmpty ? "" : "?" + queryString)) else {
            throw BiliError.invalidLink
        }
        var headers = ["User-Agent": Self.userAgent, "Referer": Self.referer, "Accept": "application/json"]
        if let cookie = cookies.headerValue { headers["Cookie"] = cookie }
        let started = Date()
        let response = try await transport.send(HTTPRequest(url: url, headers: headers))
        let ms = Date().timeIntervalSince(started) * 1000
        guard (200..<300).contains(response.status) else {
            logger.warn(.api, path, ["status": .init(response.status), "ms": .init(ms.rounded())])
            // 412 is risk control; fresh fingerprint cookies usually clear it once.
            if response.status == 412 && !retried && path != "/x/frontend/finger/spi" {
                cookies.remove("buvid3")
                cookies.remove("buvid4")
                try await ensureRiskCookies()
                return try await get(path, query: query, signed: signed, retried: true)
            }
            throw BiliError.http(response.status)
        }
        do {
            let envelope = try JSONDecoder().decode(BiliEnvelope<T>.self, from: response.body)
            logger.info(.api, path, ["status": .init(response.status), "code": .init(envelope.code), "ms": .init(ms.rounded())])
            return envelope
        } catch {
            logger.error(.api, "\(path) decode failed", ["error": .init(String(describing: error))])
            throw BiliError.decoding(String(describing: error))
        }
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter BiliClientTests`
Expected: 8 tests pass. Then run the full suite.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Bilibili API client with WBI signing and risk-control cookies"
```

---
### Task 9: DashHLS part 1, MP4 box reading and the SIDX parser

**Files:**
- Modify: `Package.swift`
- Create: `Sources/DashHLS/BoxReader.swift`, `Sources/DashHLS/SidxParser.swift`
- Test: `Tests/DashHLSTests/MP4Builder.swift`, `Tests/DashHLSTests/SidxParserTests.swift`

**Interfaces:**
- Consumes: `ByteRange`, `MediaSegment` (BiliShared).
- Produces: `BoxHeader` (`type`, `start`, `headerSize`, `end`, `payloadStart`), `BoxReader.boxes(in:from:to:)`, `BoxReader.uint16/uint32/uint64(_:_:)`; `SidxParser.parse(_ bytes: [UInt8], absoluteStart: Int64) -> [MediaSegment]?` (byte offsets are absolute file offsets; `bytes` starts at file offset `absoluteStart`). Test helper `MP4Builder` (test target only).

- [ ] **Step 1: Register the module**

In `Package.swift` add `"DashHLS"` to the product and:

```swift
        .target(name: "DashHLS", dependencies: ["BiliShared"]),
        .testTarget(name: "DashHLSTests", dependencies: ["DashHLS", "BiliShared"]),
```

- [ ] **Step 2: Add the test MP4 builder**

`Tests/DashHLSTests/MP4Builder.swift`:

```swift
enum MP4Builder {
    static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xff)] }
    static func be32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (24 - 8 * UInt32($0))) & 0xff) } }
    static func be64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (56 - 8 * UInt64($0))) & 0xff) } }

    static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }

    /// refs: (reference word including the type bit, duration in timescale units)
    static func sidx(version: UInt8, timescale: UInt32, earliest: UInt64, firstOffset: UInt64, refs: [(UInt32, UInt32)]) -> [UInt8] {
        var payload: [UInt8] = [version, 0, 0, 0] + be32(1) + be32(timescale)
        if version == 0 {
            payload += be32(UInt32(earliest)) + be32(UInt32(firstOffset))
        } else {
            payload += be64(earliest) + be64(firstOffset)
        }
        payload += [0, 0] + be16(UInt16(refs.count))
        for (reference, duration) in refs {
            payload += be32(reference) + be32(duration) + be32(0x9000_0000)
        }
        return box("sidx", payload)
    }

    static func hvcC(nalTypes: [UInt8]) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 22) + [UInt8(nalTypes.count)]
        for type in nalTypes {
            payload += [type & 0x3f] + be16(1) + be16(2) + [0xAA, 0xBB]
        }
        return box("hvcC", payload)
    }

    static func initSegment(entryType: String, nalTypes: [UInt8]) -> [UInt8] {
        let entry = box(entryType, [UInt8](repeating: 0, count: 78) + hvcC(nalTypes: nalTypes))
        let stsd = box("stsd", [0, 0, 0, 0] + be32(1) + entry)
        let trak = box("trak", box("tkhd", [UInt8](repeating: 0, count: 84)) + box("mdia", box("minf", box("stbl", stsd))))
        let moov = box("moov", box("mvhd", [UInt8](repeating: 0, count: 100)) + trak)
        return box("ftyp", Array("iso6".utf8) + be32(0)) + moov
    }
}
```

- [ ] **Step 3: Write the failing tests**

`Tests/DashHLSTests/SidxParserTests.swift`:

```swift
import XCTest
import BiliShared
@testable import DashHLS

final class SidxParserTests: XCTestCase {
    func testVersion0AfterAnotherBox() throws {
        let bytes = MP4Builder.box("free", []) + MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0,
                                                                  refs: [(1000, 2000), (2000, 2000), (1500, 1000)])
        let segments = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 500))
        // sidx is 68 bytes at offset 8, so media starts at 500 + 76.
        XCTAssertEqual(segments.map(\.range), [ByteRange(start: 576, end: 1575), ByteRange(start: 1576, end: 3575), ByteRange(start: 3576, end: 5075)])
        XCTAssertEqual(segments.map(\.startTime), [0, 2, 4])
        XCTAssertEqual(segments.map(\.duration), [2, 2, 1])
        XCTAssertEqual(segments.map(\.index), [0, 1, 2])
    }

    func testVersion1WithEarliestTimeAndOffset() throws {
        let bytes = MP4Builder.sidx(version: 1, timescale: 90000, earliest: 90000, firstOffset: 10, refs: [(4000, 180000)])
        let segment = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 0)?.first)
        XCTAssertEqual(segment.startTime, 1)
        XCTAssertEqual(segment.duration, 2)
        XCTAssertEqual(segment.range.start, Int64(bytes.count) + 10)
    }

    func testHierarchicalReferencesAreSkippedButAdvanceOffsets() throws {
        let bytes = MP4Builder.sidx(version: 0, timescale: 1000, earliest: 0, firstOffset: 0, refs: [(0x8000_0000 | 100, 10), (200, 10)])
        let segments = try XCTUnwrap(SidxParser.parse(bytes, absoluteStart: 0))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].range.start, Int64(bytes.count) + 100)
    }

    func testRejectsBrokenInput() {
        XCTAssertNil(SidxParser.parse([1, 2, 3], absoluteStart: 0))
        XCTAssertNil(SidxParser.parse(MP4Builder.box("free", [0, 0]), absoluteStart: 0))
        XCTAssertNil(SidxParser.parse(MP4Builder.sidx(version: 0, timescale: 0, earliest: 0, firstOffset: 0, refs: [(10, 10)]), absoluteStart: 0))
    }

    func testBoxReaderStopsAtTruncatedBox() {
        let bytes = MP4Builder.box("ftyp", [1, 2, 3, 4]) + MP4Builder.be32(100) + Array("moov".utf8)
        XCTAssertEqual(BoxReader.boxes(in: bytes, from: 0, to: bytes.count).map(\.type), ["ftyp"])
    }
}
```

- [ ] **Step 4: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter SidxParserTests`
Expected: compile errors.

- [ ] **Step 5: Implement the box reader and parser**

`Sources/DashHLS/BoxReader.swift`:

```swift
public struct BoxHeader: Equatable, Sendable {
    public let type: String
    public let start: Int
    public let headerSize: Int
    /// Exclusive.
    public let end: Int

    public var payloadStart: Int { start + headerSize }
}

public enum BoxReader {
    public static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    public static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }

    public static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[offset + $1]) }
    }

    static func type(_ bytes: [UInt8], _ offset: Int) -> String {
        String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    /// Sibling boxes between `from` and `to`. Stops at the first malformed or truncated box, so a
    /// buffer that ends mid-file still yields the complete boxes before the cut.
    public static func boxes(in bytes: [UInt8], from: Int, to: Int) -> [BoxHeader] {
        var result: [BoxHeader] = []
        var offset = from
        let limit = min(to, bytes.count)
        while offset + 8 <= limit {
            var size = Int(uint32(bytes, offset))
            var header = 8
            if size == 1 {
                guard offset + 16 <= limit else { break }
                let large = uint64(bytes, offset + 8)
                guard large <= UInt64(Int.max) else { break }
                size = Int(large)
                header = 16
            } else if size == 0 {
                size = limit - offset
            }
            guard size >= header, offset + size <= limit else { break }
            result.append(BoxHeader(type: type(bytes, offset + 4), start: offset, headerSize: header, end: offset + size))
            offset += size
        }
        return result
    }
}
```

`Sources/DashHLS/SidxParser.swift`:

```swift
import BiliShared

public enum SidxParser {
    /// Segments from the first `sidx` box in `bytes`, which begins at file offset `absoluteStart`.
    public static func parse(_ bytes: [UInt8], absoluteStart: Int64) -> [MediaSegment]? {
        guard let box = BoxReader.boxes(in: bytes, from: 0, to: bytes.count).first(where: { $0.type == "sidx" }) else { return nil }
        var cursor = box.payloadStart
        guard cursor + 12 <= box.end else { return nil }
        let version = bytes[cursor]
        cursor += 8
        let timescale = Double(BoxReader.uint32(bytes, cursor))
        cursor += 4
        guard timescale > 0 else { return nil }

        let earliest: UInt64
        let firstOffset: UInt64
        if version == 0 {
            guard cursor + 8 <= box.end else { return nil }
            earliest = UInt64(BoxReader.uint32(bytes, cursor))
            firstOffset = UInt64(BoxReader.uint32(bytes, cursor + 4))
            cursor += 8
        } else if version == 1 {
            guard cursor + 16 <= box.end else { return nil }
            earliest = BoxReader.uint64(bytes, cursor)
            firstOffset = BoxReader.uint64(bytes, cursor + 8)
            cursor += 16
        } else {
            return nil
        }
        cursor += 2
        guard cursor + 2 <= box.end else { return nil }
        let count = Int(BoxReader.uint16(bytes, cursor))
        cursor += 2
        guard count >= 1, count <= 10_000, cursor + count * 12 <= box.end else { return nil }

        var byteCursor = absoluteStart + Int64(box.end) + Int64(firstOffset)
        var time = Double(earliest)
        var segments: [MediaSegment] = []
        for _ in 0..<count {
            let reference = BoxReader.uint32(bytes, cursor)
            let size = Int64(reference & 0x7fff_ffff)
            let duration = Double(BoxReader.uint32(bytes, cursor + 4))
            cursor += 12
            guard size > 0, let range = ByteRange(start: byteCursor, end: byteCursor + size - 1) else { return nil }
            // Type 1 points at another sidx; Bilibili's files only use media references.
            if reference >> 31 == 0 {
                segments.append(MediaSegment(index: segments.count, range: range, startTime: time / timescale, duration: duration / timescale))
            }
            byteCursor += size
            time += duration
        }
        return segments.isEmpty ? nil : segments
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter SidxParserTests`
Expected: 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add MP4 box reader and SIDX parser"
```

---

### Task 10: DashHLS part 2, the hev1 init segment fix

**Files:**
- Create: `Sources/DashHLS/InitSegmentFixer.swift`
- Test: `Tests/DashHLSTests/InitSegmentFixerTests.swift`

**Interfaces:**
- Consumes: `BoxReader` (Task 9).
- Produces: `enum InitFixResult: Equatable { case unchanged, rewritten([UInt8]), unplayable(String) }`, `InitSegmentFixer.fixHEV1(_ bytes: [UInt8]) -> InitFixResult`. Works on a buffer that holds `ftyp` + `moov` and optionally more boxes after them (the app passes the whole header buffer up to the end of the SIDX).

- [ ] **Step 1: Write the failing tests**

`Tests/DashHLSTests/InitSegmentFixerTests.swift`:

```swift
import XCTest
@testable import DashHLS

final class InitSegmentFixerTests: XCTestCase {
    func testRewritesHev1WithParameterSets() throws {
        let original = MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33, 34]) + MP4Builder.box("sidx", [1, 2, 3])
        guard case .rewritten(let fixed) = InitSegmentFixer.fixHEV1(original) else { return XCTFail("expected a rewrite") }
        XCTAssertEqual(fixed.count, original.count)
        let position = try XCTUnwrap(indexOf("hev1", in: original))
        XCTAssertEqual(Array(fixed[position..<position + 4]), Array("hvc1".utf8))
        var restored = fixed
        restored.replaceSubrange(position..<position + 4, with: Array("hev1".utf8))
        XCTAssertEqual(restored, original)
    }

    func testRefusesHev1WithoutPPS() {
        guard case .unplayable = InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "hev1", nalTypes: [32, 33])) else {
            return XCTFail("expected unplayable")
        }
    }

    func testLeavesOtherEntriesAlone() {
        XCTAssertEqual(InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "hvc1", nalTypes: [32, 33, 34])), .unchanged)
        XCTAssertEqual(InitSegmentFixer.fixHEV1(MP4Builder.initSegment(entryType: "avc1", nalTypes: [])), .unchanged)
        XCTAssertEqual(InitSegmentFixer.fixHEV1([0, 1, 2]), .unchanged)
    }

    private func indexOf(_ text: String, in bytes: [UInt8]) -> Int? {
        let needle = Array(text.utf8)
        guard bytes.count >= needle.count else { return nil }
        return (0...(bytes.count - needle.count)).first { Array(bytes[$0..<$0 + needle.count]) == needle }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter InitSegmentFixerTests`
Expected: compile errors.

- [ ] **Step 3: Implement the fixer**

`Sources/DashHLS/InitSegmentFixer.swift`:

```swift
public enum InitFixResult: Equatable, Sendable {
    case unchanged
    case rewritten([UInt8])
    case unplayable(String)
}

/// AVPlayer only plays HEVC from HLS when the sample entry is `hvc1` (parameter sets out of band).
/// Bilibili often labels HEVC `hev1`. When the `hvcC` box already carries VPS, SPS and PPS, the
/// two labels describe the same bytes, so renaming the four-character code is enough.
public enum InitSegmentFixer {
    public static func fixHEV1(_ bytes: [UInt8]) -> InitFixResult {
        var output = bytes
        var rewrote = false
        for moov in BoxReader.boxes(in: bytes, from: 0, to: bytes.count) where moov.type == "moov" {
            for entry in sampleEntries(bytes, moov) where entry.type == "hev1" {
                guard hasParameterSets(bytes, entry) else { return .unplayable("hev1 without VPS/SPS/PPS in hvcC") }
                output.replaceSubrange((entry.start + 4)..<(entry.start + 8), with: Array("hvc1".utf8))
                rewrote = true
            }
        }
        return rewrote ? .rewritten(output) : .unchanged
    }

    private static func children(_ bytes: [UInt8], _ box: BoxHeader, type: String) -> [BoxHeader] {
        BoxReader.boxes(in: bytes, from: box.payloadStart, to: box.end).filter { $0.type == type }
    }

    private static func sampleEntries(_ bytes: [UInt8], _ moov: BoxHeader) -> [BoxHeader] {
        var entries: [BoxHeader] = []
        for trak in children(bytes, moov, type: "trak") {
            for mdia in children(bytes, trak, type: "mdia") {
                for minf in children(bytes, mdia, type: "minf") {
                    for stbl in children(bytes, minf, type: "stbl") {
                        for stsd in children(bytes, stbl, type: "stsd") {
                            // stsd is a full box: version/flags and entry_count come first.
                            entries += BoxReader.boxes(in: bytes, from: stsd.payloadStart + 8, to: stsd.end)
                        }
                    }
                }
            }
        }
        return entries
    }

    private static func hasParameterSets(_ bytes: [UInt8], _ entry: BoxHeader) -> Bool {
        // A VisualSampleEntry has 78 bytes of fixed fields before its child boxes.
        let childStart = entry.payloadStart + 78
        guard childStart <= entry.end,
              let hvcC = BoxReader.boxes(in: bytes, from: childStart, to: entry.end).first(where: { $0.type == "hvcC" }) else {
            return false
        }
        var cursor = hvcC.payloadStart + 22
        guard cursor < hvcC.end else { return false }
        let arrayCount = Int(bytes[cursor])
        cursor += 1
        var found = Set<UInt8>()
        for _ in 0..<arrayCount {
            guard cursor + 3 <= hvcC.end else { return false }
            let nalType = bytes[cursor] & 0x3f
            let nalCount = Int(BoxReader.uint16(bytes, cursor + 1))
            cursor += 3
            for _ in 0..<nalCount {
                guard cursor + 2 <= hvcC.end else { return false }
                cursor += 2 + Int(BoxReader.uint16(bytes, cursor))
                guard cursor <= hvcC.end else { return false }
            }
            if nalCount > 0 { found.insert(nalType) }
        }
        // 32 = VPS, 33 = SPS, 34 = PPS.
        return found.isSuperset(of: [32, 33, 34])
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter InitSegmentFixerTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add hev1 to hvc1 init segment fix"
```

---

### Task 11: DashHLS part 3, codec mapping and HLS playlists

**Files:**
- Create: `Sources/DashHLS/CodecMapper.swift`, `Sources/DashHLS/PlaylistBuilder.swift`
- Test: `Tests/DashHLSTests/PlaylistBuilderTests.swift`

**Interfaces:**
- Consumes: `ByteRange`, `MediaSegment`.
- Produces: `HLSVideoCodec(codecs:supplemental:videoRange:)`; `CodecMapper.video(codecs:qualityID:rewriteHEV1:) -> HLSVideoCodec`; `CodecMapper.frameRate(_:) -> String`; `HLSTrack(uri:initRange:segments:)`; `HLSVariant(codec:audioCodecs:averageBandwidth:width:height:frameRate:)`; `PlaylistBuilder.media(_:) -> String`; `PlaylistBuilder.master(_:videoPlaylist:audioPlaylist:) -> String`.

- [ ] **Step 1: Write the failing tests**

`Tests/DashHLSTests/PlaylistBuilderTests.swift`:

```swift
import XCTest
import BiliShared
@testable import DashHLS

final class PlaylistBuilderTests: XCTestCase {
    func testCodecMapping() {
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.1.6.L153.90", qualityID: 120, rewriteHEV1: true),
                       HLSVideoCodec(codecs: "hvc1.1.6.L153.90", supplemental: nil, videoRange: "SDR"))
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.1.6.L153.90", qualityID: 120, rewriteHEV1: false).codecs, "hev1.1.6.L153.90")
        XCTAssertEqual(CodecMapper.video(codecs: "hev1.2.4.L153.90", qualityID: 125, rewriteHEV1: true).videoRange, "PQ")
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.08.07", qualityID: 126, rewriteHEV1: true),
                       HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "dvh1.08.07/db4h", videoRange: "HLG"))
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.08.06", qualityID: 126, rewriteHEV1: true),
                       HLSVideoCodec(codecs: "hvc1.2.4.L150", supplemental: "dvh1.08.06/db1p", videoRange: "PQ"))
        XCTAssertEqual(CodecMapper.video(codecs: "dvh1.05.06", qualityID: 126, rewriteHEV1: true).videoRange, "PQ")
        XCTAssertEqual(CodecMapper.video(codecs: "avc1.640034", qualityID: 80, rewriteHEV1: true).codecs, "avc1.640034")
    }

    func testFrameRateFormatting() {
        XCTAssertEqual(CodecMapper.frameRate("29.412"), "29.412")
        XCTAssertEqual(CodecMapper.frameRate("60"), "60.000")
        XCTAssertEqual(CodecMapper.frameRate(nil), "30.000")
        XCTAssertEqual(CodecMapper.frameRate("abc"), "30.000")
    }

    func testMediaPlaylist() {
        let segments = [
            MediaSegment(index: 0, range: ByteRange(start: 1689, end: 50_000)!, startTime: 0, duration: 4.004),
            MediaSegment(index: 1, range: ByteRange(start: 50_001, end: 90_000)!, startTime: 4.004, duration: 3.5),
        ]
        let text = PlaylistBuilder.media(HLSTrack(uri: "v.mp4", initRange: ByteRange(start: 0, end: 1104)!, segments: segments))
        XCTAssertEqual(text, """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:5
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MAP:URI="v.mp4",BYTERANGE="1105@0"
        #EXTINF:4.004,
        #EXT-X-BYTERANGE:48312@1689
        v.mp4
        #EXTINF:3.500,
        #EXT-X-BYTERANGE:40000@50001
        v.mp4
        #EXT-X-ENDLIST

        """)
    }

    func testMasterPlaylist() {
        let variant = HLSVariant(codec: HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "dvh1.08.07/db4h", videoRange: "HLG"),
                                 audioCodecs: "mp4a.40.2", averageBandwidth: 12_320_000, width: 3840, height: 2160, frameRate: "29.412")
        XCTAssertEqual(PlaylistBuilder.master(variant, videoPlaylist: "v.m3u8", audioPlaylist: "a.m3u8"), """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="default",DEFAULT=YES,AUTOSELECT=YES,URI="a.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=18480000,AVERAGE-BANDWIDTH=12320000,CODECS="hvc1.2.4.L153.b0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.07/db4h",RESOLUTION=3840x2160,FRAME-RATE=29.412,VIDEO-RANGE=HLG,AUDIO="audio"
        v.m3u8

        """)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter PlaylistBuilderTests`
Expected: compile errors.

- [ ] **Step 3: Implement codec mapping**

`Sources/DashHLS/CodecMapper.swift`:

```swift
import Foundation

public struct HLSVideoCodec: Equatable, Sendable {
    public let codecs: String
    public let supplemental: String?
    public let videoRange: String

    public init(codecs: String, supplemental: String?, videoRange: String) {
        self.codecs = codecs
        self.supplemental = supplemental
        self.videoRange = videoRange
    }
}

public enum CodecMapper {
    /// `rewriteHEV1` is true only when the served init segment really was rewritten to `hvc1`
    /// (BTR mode); in direct mode AVPlayer reads Bilibili's original bytes.
    public static func video(codecs: String, qualityID: Int, rewriteHEV1: Bool) -> HLSVideoCodec {
        // Dolby Vision profile 8 is declared as its HEVC base layer plus a supplemental codec, so
        // devices without Dolby Vision still play the base layer.
        if codecs == "dvh1.08.07" || codecs == "dvh1.08.03" {
            return HLSVideoCodec(codecs: "hvc1.2.4.L153.b0", supplemental: "\(codecs)/db4h", videoRange: "HLG")
        }
        if codecs == "dvh1.08.06" {
            return HLSVideoCodec(codecs: "hvc1.2.4.L150", supplemental: "\(codecs)/db1p", videoRange: "PQ")
        }
        if codecs.hasPrefix("dvh1.05") {
            return HLSVideoCodec(codecs: codecs, supplemental: nil, videoRange: "PQ")
        }
        let mapped = rewriteHEV1 && codecs.hasPrefix("hev1") ? "hvc1" + codecs.dropFirst(4) : codecs
        // 125 is 真彩 HDR (HDR10).
        return HLSVideoCodec(codecs: mapped, supplemental: nil, videoRange: qualityID == 125 ? "PQ" : "SDR")
    }

    public static func frameRate(_ text: String?) -> String {
        guard let text, let value = Double(text), value > 0 else { return "30.000" }
        return String(format: "%.3f", value)
    }
}
```

- [ ] **Step 4: Implement the playlist builder**

`Sources/DashHLS/PlaylistBuilder.swift`:

```swift
import Foundation
import BiliShared

public struct HLSTrack: Sendable {
    public let uri: String
    /// ftyp + moov.
    public let initRange: ByteRange
    public let segments: [MediaSegment]

    public init(uri: String, initRange: ByteRange, segments: [MediaSegment]) {
        self.uri = uri
        self.initRange = initRange
        self.segments = segments
    }
}

public struct HLSVariant: Sendable {
    public let codec: HLSVideoCodec
    public let audioCodecs: String
    /// Video plus audio, bits per second.
    public let averageBandwidth: Int
    public let width: Int
    public let height: Int
    public let frameRate: String

    public init(codec: HLSVideoCodec, audioCodecs: String, averageBandwidth: Int, width: Int, height: Int, frameRate: String) {
        self.codec = codec
        self.audioCodecs = audioCodecs
        self.averageBandwidth = averageBandwidth
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

public enum PlaylistBuilder {
    public static func media(_ track: HLSTrack) -> String {
        let target = Int((track.segments.map(\.duration).max() ?? 1).rounded(.up))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, target))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MAP:URI=\"\(track.uri)\",BYTERANGE=\"\(track.initRange.length)@\(track.initRange.start)\"",
        ]
        for segment in track.segments {
            lines.append("#EXTINF:\(String(format: "%.3f", segment.duration)),")
            lines.append("#EXT-X-BYTERANGE:\(segment.range.length)@\(segment.range.start)")
            lines.append(track.uri)
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func master(_ variant: HLSVariant, videoPlaylist: String, audioPlaylist: String) -> String {
        var attributes = [
            "BANDWIDTH=\(Int(Double(variant.averageBandwidth) * 1.5))",
            "AVERAGE-BANDWIDTH=\(variant.averageBandwidth)",
            "CODECS=\"\(variant.codec.codecs),\(variant.audioCodecs)\"",
        ]
        if let supplemental = variant.codec.supplemental {
            attributes.append("SUPPLEMENTAL-CODECS=\"\(supplemental)\"")
        }
        attributes += [
            "RESOLUTION=\(variant.width)x\(variant.height)",
            "FRAME-RATE=\(variant.frameRate)",
            "VIDEO-RANGE=\(variant.codec.videoRange)",
            "AUDIO=\"audio\"",
        ]
        let lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-INDEPENDENT-SEGMENTS",
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"default\",DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioPlaylist)\"",
            "#EXT-X-STREAM-INF:" + attributes.joined(separator: ","),
            videoPlaylist,
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter PlaylistBuilderTests`
Expected: 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add HLS codec mapping and playlist builder"
```

---
### Task 12: Ripper part 1, node catalog and media URL rules

The Ripper module is the Swift port of BTR's download core (`src/range-core.js`, `src/cdn-resolver.js`, `src/idm-downloader.js` in BTR 2026.10.8.1, checked out at `D:\Repos\Apps\Bilibili-thread-ripper`). When a rule below is unclear, read the matching JS function; the port follows it unless this plan says otherwise.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Ripper/LICENSE-BTR.txt`, `Sources/Ripper/NodeCatalog.swift`
- Test: `Tests/RipperTests/NodeCatalogTests.swift`

**Interfaces:**
- Produces: `NodeAddress(host:port:)`; `enum NodeMode: Equatable, Sendable { case mainland, overseas, custom([NodeAddress]) }`; `MediaURLPolicy` (`allowsURL`, `.bilibili`, `.any`); `NodeCatalog.mainland`, `.overseas`, `host(of:)`, `nodeKey(of:)` (host plus `:port` when there is one), `address(of:)` (path plus query), `isAkamai(_:)`, `swapHost(_:to:allowAkamai:)`, `representationURLs(primary:backups:mode:policy:)`.

- [ ] **Step 1: Register the module and add the licence**

In `Package.swift` add `"Ripper"` to the product and:

```swift
        .target(name: "Ripper", dependencies: ["BiliShared", "DevLog"], exclude: ["LICENSE-BTR.txt"]),
        .testTarget(name: "RipperTests", dependencies: ["Ripper", "BiliShared", "DevLog"]),
```

Create `Sources/Ripper/LICENSE-BTR.txt` with this exact text (BTR's licence):

```
The download engine in this module is a Swift port of Bilibili-thread-ripper
(https://github.com/MrTangLuyao/Bilibili-thread-ripper), used under the MIT License:

MIT License

Copyright (c) 2026 Bilibili-thread-ripper contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write the failing tests**

`Tests/RipperTests/NodeCatalogTests.swift`:

```swift
import XCTest
@testable import Ripper

final class NodeCatalogTests: XCTestCase {
    let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv&upsig=x"
    let backup = "https://upos-sz-mirrorali.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=alibv"

    func testOverseasSwapsTheSignedAddressOntoOverseasNodes() {
        let urls = NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .overseas, policy: .bilibili)
        XCTAssertEqual(urls.map(NodeCatalog.host(of:)), NodeCatalog.overseas)
        XCTAssertTrue(urls.allSatisfy { NodeCatalog.address(of: $0) == "/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv&upsig=x" })
    }

    func testMainlandKeepsOriginalsFirstAndDeduplicates() {
        let urls = NodeCatalog.representationURLs(primary: primary, backups: [backup], mode: .mainland, policy: .bilibili)
        XCTAssertEqual(Array(urls.prefix(2)), [primary, backup])
        XCTAssertEqual(urls.count, 9)
        XCTAssertEqual(Set(urls).count, urls.count)
    }

    func testAkamaiOnlyAddressesBecomeDonors() {
        let akamai = "https://upos-hz-mirrorakam.akamaized.net/upgcxcode/1/2/3/v.m4s?deadline=9&os=akam&hdnts=x"
        let urls = NodeCatalog.representationURLs(primary: akamai, backups: [], mode: .overseas, policy: .bilibili)
        XCTAssertEqual(urls.first, akamai)
        XCTAssertEqual(urls.count, 1 + NodeCatalog.overseas.count)
        XCTAssertNil(NodeCatalog.swapHost(akamai, to: NodeAddress(host: "upos-sz-mirrorcosov.bilivideo.com")))
    }

    func testSwapClearsNonStandardPort() {
        let withPort = "https://upos-sz-mirrorcos.bilivideo.com:4483/upgcxcode/v.m4s?deadline=9"
        let swapped = NodeCatalog.swapHost(withPort, to: NodeAddress(host: "upos-sz-mirrorcosov.bilivideo.com"))
        XCTAssertEqual(swapped, "https://upos-sz-mirrorcosov.bilivideo.com/upgcxcode/v.m4s?deadline=9")
    }

    func testPolicyRejectsForeignHosts() {
        XCTAssertTrue(NodeCatalog.representationURLs(primary: "https://evil.example.com/v.m4s", backups: [], mode: .overseas, policy: .bilibili).isEmpty)
        XCTAssertFalse(MediaURLPolicy.bilibili.allowsURL(URL(string: "http://upos-sz-mirrorcos.bilivideo.com/v.m4s")!))
        XCTAssertFalse(MediaURLPolicy.bilibili.allowsURL(URL(string: "https://upos-sz-mirrorcos.bilivideo.com/v.txt")!))
    }

    func testCustomNodesWithPortsForTests() {
        let local = "http://127.0.0.1:9001/v.mp4?deadline=1"
        let urls = NodeCatalog.representationURLs(primary: local, backups: [],
                                                  mode: .custom([NodeAddress(host: "127.0.0.1", port: 9001), NodeAddress(host: "127.0.0.1", port: 9002)]),
                                                  policy: .any)
        XCTAssertEqual(urls, [local, "http://127.0.0.1:9002/v.mp4?deadline=1"])
        XCTAssertEqual(urls.map(NodeCatalog.nodeKey(of:)), ["127.0.0.1:9001", "127.0.0.1:9002"])
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter NodeCatalogTests`
Expected: compile errors.

- [ ] **Step 4: Implement the catalog**

`Sources/Ripper/NodeCatalog.swift`:

```swift
import Foundation

public struct NodeAddress: Hashable, Sendable {
    public let host: String
    public let port: Int?

    public init(host: String, port: Int? = nil) {
        self.host = host.lowercased()
        self.port = port
    }
}

public enum NodeMode: Equatable, Sendable {
    case mainland
    case overseas
    /// Explicit nodes, as BTR's custom mode; the simulator integration test also uses it for localhost nodes.
    case custom([NodeAddress])
}

public struct MediaURLPolicy: Sendable {
    public let allowsURL: @Sendable (URL) -> Bool

    public init(allowsURL: @escaping @Sendable (URL) -> Bool) {
        self.allowsURL = allowsURL
    }

    /// Signed download addresses are only ever sent to Bilibili's own media hosts.
    public static let bilibili = MediaURLPolicy { url in
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        guard path.hasSuffix(".m4s") || path.hasSuffix(".mp4") || path.hasSuffix(".flv") else { return false }
        return NodeCatalog.mediaHostSuffixes.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static let any = MediaURLPolicy { _ in true }
}

public enum NodeCatalog {
    public static let mainland = [
        "upos-sz-mirrorali.bilivideo.com",
        "upos-sz-mirrorhw.bilivideo.com",
        "upos-sz-mirrorbos.bilivideo.com",
        "upos-sz-mirror08c.bilivideo.com",
        "upos-sz-mirrorbd.bilivideo.com",
        "upos-sz-mirror14b.bilivideo.com",
        "upos-sz-estgoss.bilivideo.com",
        "upos-sz-mirrorcos.bilivideo.com",
    ]

    public static let overseas = [
        "upos-sz-mirrorcosov.bilivideo.com",
        "upos-sz-mirroraliov.bilivideo.com",
        "cn-hk-eq-01-01.bilivideo.com",
        "cn-hk-eq-01-03.bilivideo.com",
    ]

    static let mediaHostSuffixes = [
        "bilivideo.com", "bilivideo.cn", "bilivideo.net", "akamaized.net", "szbdyd.com",
        "hdslb.com", "xycdn.com", "mountaintoys.cn", "nexusedgeio.com", "ahdohpiechei.com",
    ]

    public static func host(of url: String) -> String {
        URLComponents(string: url)?.host?.lowercased() ?? ""
    }

    public static func nodeKey(of url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return "" }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    /// The signed address without its node: the same address can be asked of any node.
    public static func address(of url: String) -> String {
        guard let components = URLComponents(string: url) else { return "" }
        return components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    public static func isAkamai(_ url: String) -> Bool {
        host(of: url).hasSuffix(".akamaized.net")
    }

    public static func swapHost(_ url: String, to node: NodeAddress, allowAkamai: Bool = false) -> String? {
        if !allowAkamai && isAkamai(url) { return nil }
        guard var components = URLComponents(string: url) else { return nil }
        components.host = node.host
        // Setting the host alone would keep a peer CDN's non-standard port, such as :4483.
        components.port = node.port
        return components.string
    }

    static func nodes(for mode: NodeMode) -> [NodeAddress] {
        switch mode {
        case .mainland: return mainland.map { NodeAddress(host: $0) }
        case .overseas: return overseas.map { NodeAddress(host: $0) }
        case .custom(let nodes): return nodes
        }
    }

    /// BTR `representationUrls`: the addresses Bilibili gave that suit the mode, then the signed
    /// address swapped onto every node of the mode.
    public static func representationURLs(primary: String, backups: [String], mode: NodeMode, policy: MediaURLPolicy) -> [String] {
        func allowed(_ url: String) -> Bool { URL(string: url).map(policy.allowsURL) ?? false }
        let originals = deduplicated(([primary] + backups).filter(allowed))
        let nodes = nodes(for: mode)
        // Some overseas accounts only get akamaized.net addresses; the nodes accept those
        // signatures too, so then every one of them is tried on every node.
        let synthetic: [String]
        if let donor = originals.first(where: { !isAkamai($0) }) {
            synthetic = nodes.compactMap { swapHost(donor, to: $0) }
        } else {
            synthetic = nodes.flatMap { node in originals.compactMap { swapHost($0, to: node, allowAkamai: true) } }
        }
        let allowedOriginals: [String]
        switch mode {
        case .custom(let list):
            let hosts = Set(list.map(\.host))
            allowedOriginals = originals.filter { hosts.contains(host(of: $0)) }
        case .overseas:
            allowedOriginals = originals.filter { !mainland.contains(host(of: $0)) }
        case .mainland:
            allowedOriginals = originals.filter { mainland.contains(host(of: $0)) }
        }
        return deduplicated(allowedOriginals + synthetic.filter(allowed))
    }

    static func deduplicated(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter NodeCatalogTests`
Expected: 6 tests pass. If `testSwapClearsNonStandardPort` or the dedupe count differs because `URLComponents.string` re-encodes the query differently on one platform, compare with `NodeCatalog.address(of:)` instead of full strings and note it in the commit message; do not change the rules.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Ripper node catalog (BTR cdn-resolver port, part 1)"
```

---

### Task 13: Ripper part 2, ban list

**Files:**
- Create: `Sources/Ripper/BanList.swift`
- Test: `Tests/RipperTests/BanListTests.swift`

**Interfaces:**
- Consumes: `NodeCatalog.nodeKey(of:)`, `NodeCatalog.address(of:)`.
- Produces: `BanList(limit: Int = 2)` with `record(url:receivedBytes:status:) -> Bool`, `success(url:)`, `allows(_:)`, `allowsNode(_:)`, `allowsAddress(_:)`, `bannedNodes() -> [String]`, `reset()`, `onBan: ((node: String, strikes: Int, kind: BanKind) -> Void)?`, `enum BanKind { case node, address, pair }`.

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/BanListTests.swift`:

```swift
import XCTest
@testable import Ripper

final class BanListTests: XCTestCase {
    func url(_ node: String, _ file: String) -> String { "https://\(node).bilivideo.com/upgcxcode/\(file).m4s?deadline=1" }

    func testTwoSilentFailuresBanTheNode() {
        let bans = BanList()
        XCTAssertFalse(bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil))
        XCTAssertTrue(bans.record(url: url("a", "f1"), receivedBytes: 0, status: nil))
        XCTAssertFalse(bans.allows(url("a", "f2")))
        XCTAssertEqual(bans.bannedNodes(), ["a.bilivideo.com"])
    }

    func testPartialTransfersAreNotStrikes() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 10, status: nil)
        bans.record(url: url("a", "f1"), receivedBytes: 10, status: nil)
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }

    func testRefusalByAGoodNodeBlamesTheAddress() {
        let bans = BanList()
        bans.success(url: url("a", "f1"))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allows(url("b", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }

    func testRefusalOfAGoodAddressByAGoodNodeBlamesOnlyThePair() {
        let bans = BanList()
        var kinds: [BanList.BanKind] = []
        bans.onBan = { _, _, kind in kinds.append(kind) }
        bans.success(url: url("a", "f1"))
        bans.success(url: url("b", "f2"))
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f2"), receivedBytes: 0, status: 403)
        XCTAssertFalse(bans.allows(url("a", "f2")))
        XCTAssertTrue(bans.allows(url("b", "f2")))
        XCTAssertTrue(bans.allows(url("a", "f1")))
        XCTAssertEqual(kinds, [.pair])
    }

    func testRefusalCountsAgainstNobodyUntilSomethingDelivers() {
        let bans = BanList()
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        bans.record(url: url("a", "f1"), receivedBytes: 0, status: 403)
        XCTAssertTrue(bans.allows(url("a", "f1")))
        bans.success(url: url("b", "f1"))
        XCTAssertFalse(bans.allowsNode(url("a", "f1")))
        bans.reset()
        XCTAssertTrue(bans.allows(url("a", "f1")))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter BanListTests`
Expected: compile errors.

- [ ] **Step 3: Implement the ban list**

`Sources/Ripper/BanList.swift`:

```swift
import BiliShared

/// BTR `createBanList`. A node that twice fails without sending a byte is skipped for the rest of
/// the video. For HTTP 4xx, what has delivered decides who is blamed: a refusal by a node that
/// serves other addresses blames the address; a refusal of an address other nodes serve blames
/// the node; when both are known good, only that node and address pair is dropped.
public final class BanList: @unchecked Sendable {
    public enum BanKind: Equatable, Sendable {
        case node, address, pair
    }

    private struct State {
        var emptyReplies: [String: Int] = [:]
        var goodNodes = Set<String>()
        var goodAddresses = Set<String>()
        var reported = Set<String>()
        var banned = Set<String>()
    }

    private let state = Locked(State())
    private let limit: Int
    public var onBan: ((_ node: String, _ strikes: Int, _ kind: BanKind) -> Void)?

    public init(limit: Int = 2) {
        self.limit = max(1, limit)
    }

    @discardableResult
    public func record(url: String, receivedBytes: Int64, status: Int?) -> Bool {
        guard receivedBytes == 0 else { return false }
        let node = NodeCatalog.nodeKey(of: url)
        guard !node.isEmpty else { return false }
        let refused = status.map { (400..<500).contains($0) } ?? false
        let key = "\(node)\n\(NodeCatalog.address(of: url))\n\(refused ? "refused" : "")"
        let added = state.withLock { value -> [(String, Int)] in
            value.emptyReplies[key, default: 0] += 1
            return judge(&value)
        }
        report(added, url: url)
        return !added.isEmpty
    }

    public func success(url: String) {
        let node = NodeCatalog.nodeKey(of: url)
        let address = NodeCatalog.address(of: url)
        guard !node.isEmpty else { return }
        let added = state.withLock { value -> [(String, Int)] in
            if value.goodNodes.contains(node) && value.goodAddresses.contains(address) { return [] }
            value.goodNodes.insert(node)
            value.goodAddresses.insert(address)
            return judge(&value)
        }
        report(added, url: url)
    }

    public func allows(_ url: String) -> Bool {
        let node = NodeCatalog.nodeKey(of: url)
        let address = NodeCatalog.address(of: url)
        return state.withLock {
            !$0.banned.contains("node:\(node)") && !$0.banned.contains("address:\(address)") && !$0.banned.contains("pair:\(node) \(address)")
        }
    }

    public func allowsNode(_ url: String) -> Bool {
        let node = NodeCatalog.nodeKey(of: url)
        return state.withLock { !$0.banned.contains("node:\(node)") }
    }

    public func allowsAddress(_ url: String) -> Bool {
        let address = NodeCatalog.address(of: url)
        return state.withLock { !$0.banned.contains("address:\(address)") }
    }

    public func bannedNodes() -> [String] {
        state.current.banned.filter { $0.hasPrefix("node:") }.map { String($0.dropFirst(5)) }.sorted()
    }

    public func reset() {
        state.withLock { $0 = State() }
    }

    private func judge(_ value: inout State) -> [(String, Int)] {
        var strikes: [String: Int] = [:]
        for (key, count) in value.emptyReplies {
            let parts = key.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let node = parts[0]
            let address = parts[1]
            let refused = parts[2] == "refused"
            let blamed: String
            if !refused {
                blamed = "node:\(node)"
            } else if value.goodNodes.contains(node) {
                blamed = value.goodAddresses.contains(address) ? "pair:\(node) \(address)" : "address:\(address)"
            } else if value.goodAddresses.contains(address) {
                blamed = "node:\(node)"
            } else {
                blamed = ""
            }
            if !blamed.isEmpty { strikes[blamed, default: 0] += count }
        }
        value.banned = Set(strikes.filter { $0.value >= limit }.map(\.key))
        var added: [(String, Int)] = []
        for key in value.banned.sorted() where !value.reported.contains(key) {
            value.reported.insert(key)
            added.append((key, strikes[key] ?? 0))
        }
        return added
    }

    private func report(_ added: [(String, Int)], url: String) {
        for (key, strikes) in added {
            if key.hasPrefix("node:") {
                onBan?(String(key.dropFirst(5)), strikes, .node)
            } else {
                onBan?(NodeCatalog.nodeKey(of: url), strikes, key.hasPrefix("pair:") ? .pair : .address)
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter BanListTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Ripper ban list (BTR createBanList port)"
```

---

### Task 14: Ripper part 3, resolver (node health, speeds, candidate lists)

**Files:**
- Create: `Sources/Ripper/Resolver.swift`
- Test: `Tests/RipperTests/ResolverTests.swift`

**Interfaces:**
- Consumes: `NodeCatalog`, `BanList`, `MonotonicClock`, `Locked`.
- Produces: `Resolver(primary:backups:mode:policy:bans:clock:)` with `mode`, `bans`, `replaceURLs(primary:backups:)`, `allURLs()`, `urls()`, `allows(_:)`, `ordered(pieceIndex:excluding:)`, `rangeCandidates()`, `startupCandidates()`, `rescueCandidates()`, `success(_:bps:)`, `sample(_:bps:)`, `failure(_:status:receivedBytes:)`, `speed(_:) -> Double`, `status() -> [Resolver.NodeStatus]` (`node`, `state` one of `healthy`/`blocked`/`banned`/`untested`, `bps`).

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/ResolverTests.swift`:

```swift
import XCTest
import BiliShared
@testable import Ripper

final class ResolverTests: XCTestCase {
    let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv"
    var manual: ManualClock!
    var resolver: Resolver!

    override func setUp() {
        manual = ManualClock(100_000)
        resolver = Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList(), clock: manual.clock)
    }

    func node(_ index: Int) -> String { resolver.urls()[index] }

    func testOrderedRotates() {
        let first = resolver.ordered()
        let second = resolver.ordered()
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(Array(second), Array(first[1...] + first[..<1]))
    }

    func testFailureBacksOff() {
        let a = node(0)
        resolver.failure(a, status: 503, receivedBytes: 0)
        XCTAssertFalse(resolver.ordered().contains(a))
        manual.advance(6_001)
        XCTAssertTrue(resolver.ordered().contains(a))
    }

    func testSpeedIsAveragedAndExpires() {
        let a = node(0)
        resolver.success(a, bps: 1_000_000)
        XCTAssertEqual(resolver.speed(a), 1_000_000)
        resolver.success(a, bps: 2_000_000)
        XCTAssertEqual(resolver.speed(a), 1_350_000, accuracy: 0.1)
        manual.advance(90_001)
        XCTAssertEqual(resolver.speed(a), 0)
    }

    func testSampleMeasuresWithoutProvingTheAddress() {
        let a = node(1)
        resolver.sample(a, bps: 500_000)
        XCTAssertEqual(resolver.speed(a), 500_000)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "untested")
    }

    func testNewSignatureKeepsTheRouteSpeed() {
        let a = node(0)
        resolver.success(a, bps: 3_000_000)
        resolver.replaceURLs(primary: primary.replacingOccurrences(of: "deadline=9", with: "deadline=99"), backups: [])
        let renewed = node(0)
        XCTAssertNotEqual(renewed, a)
        XCTAssertEqual(resolver.speed(renewed), 3_000_000)
    }

    func testRangeCandidatesWarmUpThenPreferMeasured() {
        XCTAssertEqual(resolver.rangeCandidates().count, 4)
        let fast = node(2)
        resolver.success(fast, bps: 9_000_000)
        for _ in 0..<3 { _ = resolver.rangeCandidates() }
        let after = resolver.rangeCandidates()
        XCTAssertEqual(after.first, fast)
        XCTAssertGreaterThanOrEqual(after.count, 3)
    }

    func testStatusShowsBans() {
        let a = node(0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        resolver.failure(a, status: nil, receivedBytes: 0)
        XCTAssertEqual(resolver.status().first { $0.node == NodeCatalog.nodeKey(of: a) }?.state, "banned")
        XCTAssertFalse(resolver.urls().contains(a))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter ResolverTests`
Expected: compile errors.

- [ ] **Step 3: Implement the resolver**

`Sources/Ripper/Resolver.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter ResolverTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Ripper resolver (BTR createResolver port)"
```

---

### Task 15: Ripper part 4, automatic connection count

**Files:**
- Create: `Sources/Ripper/AutoConcurrency.swift`
- Test: `Tests/RipperTests/AutoConcurrencyTests.swift`

**Interfaces:**
- Consumes: `MonotonicClock`, `Locked`.
- Produces: `AutoConcurrency(clock:)` with `static ladder`, `threads`, `onChange: ((threads, previous, reason) -> Void)?`, `delivered(_ bytes: Int64)`, `activity()`, `demand(active:limit:queued:)`, `stall(_:) -> Bool`, `buffer(ahead:playing:) -> Bool`, `slow() -> Bool`, `pushback(status:) -> Bool`, `newSession()`, `status() -> AutoConcurrency.Status` (`threads`, `reason`, `throughputBps`, `saturation`, `inStartup`).

This is BTR's `createAutoConcurrency` with the same constants. One shared instance lives for the whole app (BTR keeps one per page).

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/AutoConcurrencyTests.swift`:

```swift
import XCTest
import BiliShared
@testable import Ripper

final class AutoConcurrencyTests: XCTestCase {
    var manual: ManualClock!
    var auto: AutoConcurrency!

    override func setUp() {
        manual = ManualClock(100_000)
        auto = AutoConcurrency(clock: manual.clock)
    }

    func testNewSessionStartsAt16AndComesBackWhenAhead() {
        XCTAssertEqual(auto.threads, 8)
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        XCTAssertTrue(auto.status().inStartup)
        manual.advance(3_000)
        auto.buffer(ahead: 20, playing: true)
        XCTAssertEqual(auto.threads, 12)
        manual.advance(3_000)
        auto.buffer(ahead: 20, playing: true)
        XCTAssertEqual(auto.threads, 8)
        XCTAssertFalse(auto.status().inStartup)
    }

    func testStallClimbsAndRespectsCooldown() {
        auto.newSession()
        XCTAssertFalse(auto.stall())
        manual.advance(3_000)
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 24)
    }

    func testPushbackStepsDownAndBlocksThatLevel() {
        auto.newSession()
        manual.advance(3_000)
        auto.stall()
        XCTAssertEqual(auto.threads, 24)
        XCTAssertTrue(auto.pushback(status: 429))
        XCTAssertEqual(auto.threads, 16)
        manual.advance(3_000)
        XCTAssertFalse(auto.stall())
        XCTAssertEqual(auto.threads, 16)
        manual.advance(180_001)
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 24)
    }

    func testFruitlessTrialIsTakenBack() {
        auto.demand(active: 8, limit: 8, queued: 4)
        for _ in 0..<10 {
            auto.delivered(1_000_000)
            manual.advance(500)
        }
        XCTAssertTrue(auto.stall())
        XCTAssertEqual(auto.threads, 12)
        for _ in 0..<21 {
            auto.delivered(200_000)
            manual.advance(500)
        }
        XCTAssertEqual(auto.threads, 8)
    }

    func testLowBufferPressureClimbs() {
        for step in [0.0, 600, 600, 1_100] {
            manual.advance(step)
            auto.activity()
            auto.buffer(ahead: 3, playing: true)
        }
        XCTAssertEqual(auto.threads, 12)
    }

    func testOnChangeReportsSteps() {
        var seen: [Int] = []
        auto.onChange = { threads, _, _ in seen.append(threads) }
        auto.newSession()
        XCTAssertEqual(seen, [16])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter AutoConcurrencyTests`
Expected: compile errors.

- [ ] **Step 3: Implement it**

`Sources/Ripper/AutoConcurrency.swift`:

```swift
import BiliShared

/// BTR `createAutoConcurrency`. The connection count climbs a ladder whenever downloading is not
/// keeping up (a stall, a low buffer that stops growing while bytes arrive, connections queueing
/// too long). Every step up is a trial: if throughput has not grown ten seconds later it is taken
/// back and that level rests. 412/429 step down and block the level for three minutes. Each new
/// playback starts with at least 16 connections and comes back down once the buffer is ahead.
public final class AutoConcurrency: @unchecked Sendable {
    public static let ladder = [8, 12, 16, 24, 32, 48, 64]
    static let startupLevel = 2
    static let startupComfortSeconds = 15.0
    static let startupMaxMs = 30_000.0
    static let stepCooldownMs = 2_500.0
    static let trialMs = 10_000.0
    static let windowMs = 5_000.0
    static let bucketMs = 250.0
    static let restMs = 90_000.0
    static let pushbackRestMs = 180_000.0
    static let lowBufferSeconds = 6.0
    static let pressureMs = 1_000.0
    static let activityMs = 1_500.0

    public struct Status: Equatable, Sendable {
        public let threads: Int
        public let reason: String
        public let throughputBps: Double
        public let saturation: Double
        public let inStartup: Bool
    }

    struct Trial { var from: Int; var level: Int; var at: Double; var baseline: Double; var stalled: Bool }
    struct Rest { var until: Double; var hard: Bool }
    struct Bucket { var at: Double; var bytes: Double }
    struct Span { var from: Double; var to: Double }
    struct Startup { var base: Int; var until: Double }

    struct State {
        var level = 0
        var changedAt = 0.0
        var reason = "起步"
        var steps = 0
        var trial: Trial?
        var resting: [Int: Rest] = [:]
        var buckets: [Bucket] = []
        var lastActivityAt = -Double.infinity
        var saturated = false
        var saturatedSince = 0.0
        var saturatedSpans: [Span] = []
        var aheadSamples: [(at: Double, ahead: Double)] = []
        var pressureSince = 0.0
        var startup: Startup?
    }

    typealias Change = (threads: Int, previous: Int, reason: String)

    private let state = Locked(State())
    private let clock: MonotonicClock
    public var onChange: ((_ threads: Int, _ previous: Int, _ reason: String) -> Void)?

    public init(clock: MonotonicClock = .system) {
        self.clock = clock
    }

    public var threads: Int { Self.ladder[state.current.level] }

    public func status() -> Status {
        mutate { value, at, _ in
            Status(threads: Self.ladder[value.level], reason: value.reason, throughputBps: Self.throughput(&value, at),
                   saturation: Self.saturation(&value, at), inStartup: value.startup != nil)
        }
    }

    /// A piece arrived whole. Hedge copies that lost are not delivery.
    public func delivered(_ bytes: Int64) {
        mutate { value, at, changes in
            if let last = value.buckets.last, at - last.at < Self.bucketMs {
                value.buckets[value.buckets.count - 1].bytes += Double(bytes)
            } else {
                value.buckets.append(Bucket(at: at, bytes: Double(bytes)))
            }
            Self.pruneBuckets(&value, at)
            Self.judgeTrial(&value, at, &changes)
        }
    }

    public func activity() {
        mutate { value, at, _ in value.lastActivityAt = at }
    }

    public func demand(active: Int, limit: Int, queued: Int) {
        mutate { value, at, _ in
            let saturated = active >= limit && queued > 0
            guard saturated != value.saturated else { return }
            if value.saturated { value.saturatedSpans.append(Span(from: value.saturatedSince, to: at)) }
            value.saturated = saturated
            value.saturatedSince = at
            _ = Self.saturation(&value, at)
        }
    }

    @discardableResult
    public func stall(_ reason: String = "播放卡了一下") -> Bool {
        mutate { value, at, changes in
            value.trial?.stalled = true
            return Self.stepUp(&value, reason, strong: true, at, &changes)
        }
    }

    /// The buffer ahead of the playhead, a few times a second while playing.
    @discardableResult
    public func buffer(ahead: Double, playing: Bool) -> Bool {
        mutate { value, at, changes in
            value.aheadSamples.append((at, ahead))
            while let first = value.aheadSamples.first, at - first.at > Self.pressureMs + Self.bucketMs {
                value.aheadSamples.removeFirst()
            }
            if let start = value.startup {
                if at >= start.until {
                    value.startup = nil
                } else if ahead >= Self.startupComfortSeconds && at - value.changedAt >= Self.stepCooldownMs {
                    if value.level > start.base {
                        Self.setLevel(&value, value.level - 1, "开头已经跟上，线程数降到 \(Self.ladder[value.level - 1])", nil, at, &changes)
                    }
                    if value.level <= start.base { value.startup = nil }
                }
            }
            let earlier = value.aheadSamples.first { at - $0.at >= Self.pressureMs }
            let downloading = at - value.lastActivityAt < Self.activityMs
            let pressed = playing && downloading && ahead < Self.lowBufferSeconds && earlier.map { ahead <= $0.ahead + 0.05 } == true
            if !pressed {
                value.pressureSince = 0
                return false
            }
            if value.pressureSince == 0 {
                value.pressureSince = at
                return false
            }
            if at - value.pressureSince < Self.pressureMs { return false }
            value.pressureSince = 0
            return Self.stepUp(&value, "缓冲跟不上播放", strong: false, at, &changes)
        }
    }

    /// A connection waited too long for its first byte while every slot was busy.
    @discardableResult
    public func slow() -> Bool {
        mutate { value, at, changes in
            Self.saturation(&value, at) >= 0.6 ? Self.stepUp(&value, "连接排队等太久", strong: false, at, &changes) : false
        }
    }

    @discardableResult
    public func pushback(status: Int) -> Bool {
        mutate { value, at, changes in
            Self.stepDown(&value, target: max(0, value.level - 1), restLevel: value.level, "服务器返回 \(status)",
                          restMs: Self.pushbackRestMs, hard: true, at, &changes)
        }
    }

    public func newSession() {
        mutate { value, at, changes in
            value.aheadSamples.removeAll()
            value.pressureSince = 0
            value.trial = nil
            value.buckets.removeAll()
            value.saturatedSpans.removeAll()
            if value.saturated { value.saturatedSince = at }
            let base = value.startup?.base ?? value.level
            let target = Self.startupTarget(&value, at)
            if target > value.level {
                Self.setLevel(&value, target, "开头先用 \(Self.ladder[target]) 线程", nil, at, &changes)
            }
            value.startup = value.level > base ? Startup(base: base, until: at + Self.startupMaxMs) : nil
        }
    }

    private func mutate<Result>(_ body: (inout State, Double, inout [Change]) -> Result) -> Result {
        let at = clock.nowMs()
        var changes: [Change] = []
        let result = state.withLock { body(&$0, at, &changes) }
        for change in changes { onChange?(change.threads, change.previous, change.reason) }
        return result
    }

    private static func pruneBuckets(_ value: inout State, _ at: Double) {
        while let first = value.buckets.first, at - first.at > windowMs { value.buckets.removeFirst() }
    }

    /// Bytes per second over the window, timed from first to last delivery so an idle tail is not slowness.
    private static func throughput(_ value: inout State, _ at: Double) -> Double {
        pruneBuckets(&value, at)
        guard let first = value.buckets.first, let last = value.buckets.last else { return 0 }
        let bytes = value.buckets.reduce(0) { $0 + $1.bytes }
        return bytes * 1000 / max(1000, last.at - first.at + bucketMs)
    }

    private static func saturation(_ value: inout State, _ at: Double) -> Double {
        let from = at - windowMs
        value.saturatedSpans.removeAll { $0.to <= from }
        var busy = value.saturatedSpans.reduce(0) { $0 + max(0, $1.to - max($1.from, from)) }
        if value.saturated { busy += max(0, at - max(value.saturatedSince, from)) }
        return min(1, busy / windowMs)
    }

    private static func resting(_ value: inout State, _ level: Int, _ at: Double) -> Rest? {
        guard let rest = value.resting[level] else { return nil }
        if rest.until <= at {
            value.resting[level] = nil
            return nil
        }
        return rest
    }

    private static func setLevel(_ value: inout State, _ level: Int, _ reason: String, _ trial: Trial?, _ at: Double, _ changes: inout [Change]) {
        let previous = ladder[value.level]
        value.level = level
        value.changedAt = at
        value.reason = reason
        value.steps += 1
        value.trial = trial
        value.pressureSince = 0
        changes.append((ladder[level], previous, reason))
    }

    private static func stepUp(_ value: inout State, _ reason: String, strong: Bool, _ at: Double, _ changes: inout [Change]) -> Bool {
        if at - value.changedAt < stepCooldownMs { return false }
        if resting(&value, value.level, at)?.hard == true { return false }
        var next = value.level + 1
        while next < ladder.count {
            guard let rest = resting(&value, next, at) else { break }
            if rest.hard || !strong { return false }
            next += 1
        }
        if next >= ladder.count { return false }
        let trial = Trial(from: value.level, level: next, at: at, baseline: throughput(&value, at), stalled: false)
        setLevel(&value, next, reason, trial, at, &changes)
        value.startup = nil
        return true
    }

    private static func startupTarget(_ value: inout State, _ at: Double) -> Int {
        if resting(&value, value.level, at)?.hard == true { return value.level }
        var level = value.level
        while level < startupLevel && resting(&value, level + 1, at)?.hard != true { level += 1 }
        return level
    }

    private static func stepDown(_ value: inout State, target: Int, restLevel: Int, _ reason: String, restMs: Double, hard: Bool,
                                 _ at: Double, _ changes: inout [Change]) -> Bool {
        value.resting[restLevel] = Rest(until: at + restMs, hard: hard)
        if target >= value.level { return false }
        setLevel(&value, target, reason, nil, at, &changes)
        return true
    }

    private static func judgeTrial(_ value: inout State, _ at: Double, _ changes: inout [Change]) {
        guard let trial = value.trial, at - trial.at >= trialMs else { return }
        value.trial = nil
        if trial.stalled || saturation(&value, at) < 0.6 || trial.baseline <= 0 { return }
        if throughput(&value, at) < trial.baseline {
            _ = stepDown(&value, target: trial.from, restLevel: trial.level,
                         "\(ladder[trial.level]) 线程没有比 \(ladder[trial.from]) 线程更快", restMs: restMs, hard: false, at, &changes)
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter AutoConcurrencyTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add automatic connection count (BTR createAutoConcurrency port)"
```

---

### Task 16: Ripper part 5, connection pool with priorities

**Files:**
- Create: `Sources/Ripper/ConnectionPool.swift`
- Test: `Tests/RipperTests/ConnectionPoolTests.swift`

**Interfaces:**
- Consumes: `MonotonicClock`, `Locked`.
- Produces: `enum QueueClass: Int { case critical = 0, startup = 1, ordinary = 2 }`; `ConnectionPool(limit:clock:)` with `limit`, `active`, `queued`, `setLimit(_:)`, `onChange: ((active, limit, queued) -> Void)?`, `acquire(priority:queueClass:deadline:) async throws -> ConnectionPool.Permit`; `Permit.release()` (idempotent).

Grant order (BTR `Semaphore.drainQueue`): lower class first; within a class the highest rank, where rank = priority + urgency (+12 overdue, +9 within 750 ms, +6 within 2 s of the deadline) + 20 per 900 ms of waiting for ordinary requests that have a deadline; ties by arrival.

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/ConnectionPoolTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter ConnectionPoolTests`
Expected: compile errors.

- [ ] **Step 3: Implement the pool**

`Sources/Ripper/ConnectionPool.swift`:

```swift
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
    public var onChange: ((_ active: Int, _ limit: Int, _ queued: Int) -> Void)?

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
        let ages = queueClass == .ordinary && deadline != nil
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Permit, Error>) in
                let queuedAt = clock.nowMs()
                state.withLock {
                    $0.queue.append(Waiter(id: id, priority: priority, queueClass: queueClass, deadline: deadline,
                                           ages: ages, queuedAt: queuedAt, continuation: continuation))
                }
                drain()
                // The cancellation handler may have run before the waiter was queued.
                if Task.isCancelled { cancelWaiter(id) }
            }
        } onCancel: { [weak self] in
            self?.cancelWaiter(id)
        }
    }

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
        onChange?(value.active, value.limit, value.queue.count)
    }
}
```

(Arrival order breaks ties because waiters are appended in arrival order and only a strictly better candidate replaces `best`.)

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter ConnectionPoolTests`
Expected: 5 tests pass. Run them 5 times (`for i in 1 2 3 4 5; do swift test ... ; done`) to make sure they are not flaky.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add priority connection pool (BTR Semaphore port)"
```

---
### Task 17: Ripper part 6, transport contract, simulated CDN and single attempts

**Files:**
- Create: `Sources/Ripper/Transport.swift`, `Sources/Ripper/RipperConfig.swift`, `Sources/Ripper/Meter.swift`, `Sources/Ripper/EngineStats.swift`, `Sources/Ripper/Attempt.swift`
- Test: `Tests/RipperTests/SimCDN.swift`, `Tests/RipperTests/AttemptTests.swift`

**Interfaces:**
- Consumes: `ByteRange`, `ContentRange`, `MonotonicClock`, `Locked`, `sleepMs`, `Logger`, `Resolver`, `ConnectionPool`, `AutoConcurrency`, `NodeCatalog`.
- Produces:
  - `TransportResponse(status:headers:body:)` (lowercased header names; body `AsyncThrowingStream<[UInt8], Error>`), `protocol RangeTransport: Sendable { func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse }`.
  - `RipperError` (`firstByteTimeout`, `stalled`, `attemptTimeout`, `badResponse(status:)`, `lengthMismatch(got:expected:)`, `totalMismatch`, `noNodes`, `invalidURL`, `closed`; `status`, `isTimeout`).
  - `RipperConfig` (all fields public `var`, defaults from Global Constraints: `firstByteTimeoutMs`, `stallTimeoutMs`, `attemptTimeoutMs`, `hedgeDelayMs`, `minChunkBytes`, `pieceRounds`, `retryWindowMs`, `fixedConcurrency`, `prefetchVideoBytes`, `prefetchAudioBytes`, `prefetchAheadSeconds`, `priority`).
  - `Meter` (`sampleMinBytes`, `record(bytes:elapsedMs:)`, `connectionBps`, `pieceMs`, `adaptiveMinChunk(base:rangeLength:pieceLimit:hostCount:)`, `hedgeDelayMs(configured:)`).
  - `NodeTiming`, `RipperStats` (`deliveredBytes`, `duplicateBytes`, `requests`, `failures`, `cacheHits`, `cacheMisses`, `concurrency`, `nodes`, `nodeStates`, `duplicateShare`), internal `EngineStats`.
  - Internal: `EngineContext`, `Prefix`, `AttemptProgress`, `AttemptOutput`, `AttemptRunner.run(url:piece:progress:resolver:priority:queueClass:deadline:resumeBase:)`.
  - Test double `SimCDN` (test target) used by Tasks 18 and 19.

- [ ] **Step 1: Add the simulated CDN (test target)**

`Tests/RipperTests/SimCDN.swift`:

```swift
import Foundation
import BiliShared
@testable import Ripper

/// Serves one byte pattern on every node; each node (by host[:port]) can be made slow, broken or refusing.
final class SimCDN: RangeTransport, @unchecked Sendable {
    struct Behavior: Sendable {
        var firstByteMs: Double = 2
        var bytesPerSecond: Double = 200_000_000
        var status = 206
        /// Throw connection errors until this long after the SimCDN was created.
        var failForMs: Double = 0
        var truncateAfter: Int64?
        var stallAfter: Int64?
        var wrongRange = false
    }

    struct ConnectionLost: Error {}

    let content: [UInt8]
    private let behaviors: Locked<[String: Behavior]>
    let requests = Locked<[String]>([])
    private let born = ProcessInfo.processInfo.systemUptime

    init(size: Int, behaviors: [String: Behavior] = [:]) {
        content = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        self.behaviors = Locked(behaviors)
    }

    func set(_ node: String, _ behavior: Behavior) {
        behaviors.withLock { $0[node] = behavior }
    }

    func requestCount() -> Int { requests.current.count }

    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        let node = NodeCatalog.nodeKey(of: url.absoluteString)
        requests.withLock { $0.append(node) }
        let behavior = behaviors.current[node] ?? Behavior()
        try await sleepMs(behavior.firstByteMs)
        if (ProcessInfo.processInfo.systemUptime - born) * 1000 < behavior.failForMs { throw ConnectionLost() }
        let empty = AsyncThrowingStream<[UInt8], Error> { $0.finish() }
        if behavior.status != 206 { return TransportResponse(status: behavior.status, headers: [:], body: empty) }
        guard range.end < Int64(content.count) else { return TransportResponse(status: 416, headers: [:], body: empty) }
        let served = behavior.wrongRange ? (ByteRange(start: range.start + 1, end: range.end) ?? range) : range
        let content = self.content
        let body = AsyncThrowingStream<[UInt8], Error> { continuation in
            let task = Task {
                var offset = served.start
                while offset <= served.end, !Task.isCancelled {
                    let sent = offset - served.start
                    if let limit = behavior.truncateAfter, sent >= limit { break }
                    if let limit = behavior.stallAfter, sent >= limit {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        break
                    }
                    var end = min(served.end, offset + 16 * 1024 - 1)
                    // Cut chunks exactly at the truncation and stall points.
                    if let limit = behavior.truncateAfter { end = min(end, served.start + limit - 1) }
                    if let limit = behavior.stallAfter { end = min(end, served.start + limit - 1) }
                    continuation.yield(Array(content[Int(offset)...Int(end)]))
                    let ms = Double(end - offset + 1) / behavior.bytesPerSecond * 1000
                    if ms >= 1 { try? await sleepMs(ms) } else { await Task.yield() }
                    offset = end + 1
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return TransportResponse(status: 206, headers: ["content-range": "bytes \(served.start)-\(served.end)/\(content.count)"], body: body)
    }
}

enum TestEngine {
    static let primary = "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/1/2/3/v.m4s?deadline=9&os=cosbv"
    static let cosov = "upos-sz-mirrorcosov.bilivideo.com"
    static let aliov = "upos-sz-mirroraliov.bilivideo.com"
    static let hk1 = "cn-hk-eq-01-01.bilivideo.com"
    static let hk3 = "cn-hk-eq-01-03.bilivideo.com"

    static var config: RipperConfig {
        var config = RipperConfig()
        config.firstByteTimeoutMs = 300
        config.stallTimeoutMs = 300
        config.attemptTimeoutMs = 3_000
        config.hedgeDelayMs = 100
        config.retryWindowMs = 5_000
        config.fixedConcurrency = 8
        return config
    }

    static func context(_ cdn: SimCDN, config: RipperConfig = TestEngine.config, auto: AutoConcurrency? = nil) -> EngineContext {
        EngineContext(transport: cdn, pool: ConnectionPool(limit: config.fixedConcurrency ?? auto?.threads ?? 8), config: config,
                      meter: Meter(), stats: EngineStats(), auto: auto, clock: .system, logger: Logger(session: "test"))
    }

    static func resolver() -> Resolver {
        Resolver(primary: primary, backups: [], mode: .overseas, bans: BanList())
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/RipperTests/AttemptTests.swift`:

```swift
import XCTest
import BiliShared
@testable import Ripper

final class AttemptTests: XCTestCase {
    func url(_ node: String) -> String { TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: node) }

    func run(_ cdn: SimCDN, node: String, range: ByteRange, resolver: Resolver = TestEngine.resolver()) async throws -> AttemptOutput {
        let runner = AttemptRunner(ctx: TestEngine.context(cdn))
        return try await runner.run(url: url(node), piece: range, progress: AttemptProgress(), resolver: resolver,
                                    priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { Prefix() })
    }

    func testDeliversExactBytesAndMeasuresTheNode() async throws {
        let cdn = SimCDN(size: 300_000)
        let resolver = TestEngine.resolver()
        let range = ByteRange(start: 1_000, end: 200_999)!
        let output = try await run(cdn, node: TestEngine.cosov, range: range, resolver: resolver)
        XCTAssertEqual(output.bytes, Array(cdn.content[1_000...200_999]))
        XCTAssertEqual(output.total, 300_000)
        XCTAssertGreaterThan(resolver.speed(url(TestEngine.cosov)), 0)
    }

    func testRejectsWrongStatusAndRange() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(status: 200), TestEngine.aliov: .init(wrongRange: true)])
        for node in [TestEngine.cosov, TestEngine.aliov] {
            do {
                _ = try await run(cdn, node: node, range: ByteRange(start: 0, end: 9_999)!)
                XCTFail("expected a failure for \(node)")
            } catch {
                XCTAssertNotNil((error as? RipperError)?.status)
            }
        }
    }

    func testTruncatedBodyIsALengthMismatch() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(truncateAfter: 20_000)])
        do {
            _ = try await run(cdn, node: TestEngine.cosov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? RipperError, .lengthMismatch(got: 20_000, expected: 50_000))
        }
    }

    func testTimeouts() async {
        let cdn = SimCDN(size: 100_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 1_000), TestEngine.aliov: .init(stallAfter: 16_384)])
        do {
            _ = try await run(cdn, node: TestEngine.cosov, range: ByteRange(start: 0, end: 9_999)!)
            XCTFail("expected first byte timeout")
        } catch {
            XCTAssertEqual(error as? RipperError, .firstByteTimeout)
        }
        do {
            _ = try await run(cdn, node: TestEngine.aliov, range: ByteRange(start: 0, end: 49_999)!)
            XCTFail("expected stall")
        } catch {
            XCTAssertEqual(error as? RipperError, .stalled)
        }
    }

    func testResumeBaseIsPrepended() async throws {
        let cdn = SimCDN(size: 100_000)
        let range = ByteRange(start: 0, end: 99_999)!
        let base = Prefix(bytes: 40_000, chunks: [Array(cdn.content[0..<40_000])])
        let runner = AttemptRunner(ctx: TestEngine.context(cdn))
        let output = try await runner.run(url: url(TestEngine.cosov), piece: range, progress: AttemptProgress(), resolver: TestEngine.resolver(),
                                          priority: 0, queueClass: .ordinary, deadline: nil, resumeBase: { base })
        XCTAssertEqual(output.bytes, cdn.content)
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter AttemptTests`
Expected: compile errors.

- [ ] **Step 4: Implement the transport contract, config, meter and stats**

`Sources/Ripper/Transport.swift`:

```swift
import Foundation
import BiliShared

public struct TransportResponse: Sendable {
    public let status: Int
    /// Lowercased header names.
    public let headers: [String: String]
    public let body: AsyncThrowingStream<[UInt8], Error>

    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<[UInt8], Error>) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol RangeTransport: Sendable {
    /// GET with `Range: bytes=start-end`. Returns once the response headers are in; the body streams.
    /// Cancelling the calling task, or dropping the body stream, must cancel the request.
    func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse
}

public enum RipperError: Error, Equatable, Sendable {
    case firstByteTimeout
    case stalled
    case attemptTimeout
    case badResponse(status: Int)
    case lengthMismatch(got: Int64, expected: Int64)
    case totalMismatch
    case noNodes
    case invalidURL
    case closed

    public var status: Int? {
        if case .badResponse(let status) = self { return status }
        return nil
    }

    public var isTimeout: Bool {
        self == .firstByteTimeout || self == .stalled || self == .attemptTimeout
    }
}
```

`Sources/Ripper/RipperConfig.swift`:

```swift
public struct RipperConfig: Sendable {
    public var firstByteTimeoutMs = 5_500.0
    public var stallTimeoutMs = 4_000.0
    public var attemptTimeoutMs = 15_000.0
    public var hedgeDelayMs = 900.0
    public var minChunkBytes: Int64 = 64 * 1024
    public var pieceRounds = 3
    public var retryWindowMs = 25_000.0
    /// nil = AutoConcurrency decides.
    public var fixedConcurrency: Int?
    public var prefetchVideoBytes: Int64 = 64 << 20
    public var prefetchAudioBytes: Int64 = 8 << 20
    public var prefetchAheadSeconds = 45.0
    /// Base priority of player requests; prefetch runs at 10.
    public var priority = 50.0

    public init() {}
}
```

`Sources/Ripper/Meter.swift`:

```swift
import BiliShared

/// What one connection typically delivers and how long a piece typically takes (BTR `meter`).
final class Meter: @unchecked Sendable {
    /// Shorter transfers are mostly round trip and say nothing about speed.
    static let sampleMinBytes: Int64 = 48 * 1024

    private let state = Locked((bps: 0.0, pieceMs: 0.0))

    var connectionBps: Double { state.current.bps }
    var pieceMs: Double { state.current.pieceMs }

    func record(bytes: Int64, elapsedMs: Double) {
        guard bytes >= Self.sampleMinBytes, elapsedMs > 0 else { return }
        let bps = Double(bytes) * 1000 / elapsedMs
        state.withLock { value in
            value.bps = value.bps > 0 ? value.bps * 0.7 + bps * 0.3 : bps
            value.pieceMs = value.pieceMs > 0 ? value.pieceMs * 0.7 + elapsedMs * 0.3 : elapsedMs
        }
    }

    /// A piece should keep its connection busy for a good part of a second; 64 KiB until the speed
    /// is known, never above 1 MiB, and small enough that a range still spreads over the nodes.
    func adaptiveMinChunk(base: Int64, rangeLength: Int64, pieceLimit: Int, hostCount: Int) -> Int64 {
        let bps = connectionBps
        guard bps > 0 else { return base }
        let target = Int64(bps * 0.6 / 65_536) * 65_536
        let ways = Int64(max(1, min(max(4, hostCount), pieceLimit)))
        let spread = (rangeLength + ways - 1) / ways
        return max(base, min(1 << 20, target, spread))
    }

    func hedgeDelayMs(configured: Double) -> Double {
        let typical = pieceMs
        return typical > 0 ? max(250, min(configured, (typical * 1.5).rounded())) : configured
    }
}
```

`Sources/Ripper/EngineStats.swift`:

```swift
import BiliShared

public struct NodeTiming: Equatable, Sendable {
    public var node: String
    public var requests = 0
    public var failures = 0
    /// Smoothed time to response headers.
    public var firstByteMs: Double = 0

    public init(node: String) {
        self.node = node
    }
}

public struct RipperStats: Equatable, Sendable {
    public var deliveredBytes: Int64 = 0
    /// Bytes from copies that lost a race or failed.
    public var duplicateBytes: Int64 = 0
    public var requests = 0
    public var failures = 0
    public var cacheHits = 0
    public var cacheMisses = 0
    public var concurrency = 0
    public var nodes: [NodeTiming] = []
    public var nodeStates: [Resolver.NodeStatus] = []

    public init() {}

    public var duplicateShare: Double {
        let total = deliveredBytes + duplicateBytes
        return total > 0 ? Double(duplicateBytes) / Double(total) : 0
    }
}

final class EngineStats: @unchecked Sendable {
    private let state = Locked((stats: RipperStats(), timings: [String: NodeTiming]()))

    func started(node: String) {
        state.withLock { value in
            value.stats.requests += 1
            value.timings[node, default: NodeTiming(node: node)].requests += 1
        }
    }

    func firstByte(node: String, ms: Double) {
        state.withLock { value in
            var timing = value.timings[node, default: NodeTiming(node: node)]
            timing.firstByteMs = timing.firstByteMs > 0 ? timing.firstByteMs * 0.7 + ms * 0.3 : ms
            value.timings[node] = timing
        }
    }

    func failed(node: String, wastedBytes: Int64, cancelled: Bool) {
        state.withLock { value in
            value.stats.duplicateBytes += wastedBytes
            if !cancelled {
                value.stats.failures += 1
                value.timings[node, default: NodeTiming(node: node)].failures += 1
            }
        }
    }

    func delivered(_ bytes: Int64) {
        state.withLock { $0.stats.deliveredBytes += bytes }
    }

    func cache(hit: Bool) {
        state.withLock { value in
            if hit { value.stats.cacheHits += 1 } else { value.stats.cacheMisses += 1 }
        }
    }

    func snapshot() -> RipperStats {
        state.withLock { value in
            var stats = value.stats
            stats.nodes = value.timings.values.sorted { $0.node < $1.node }
            return stats
        }
    }
}
```

- [ ] **Step 5: Implement the attempt runner**

`Sources/Ripper/Attempt.swift`:

```swift
import Foundation
import BiliShared
import DevLog

struct EngineContext: @unchecked Sendable {
    let transport: RangeTransport
    let pool: ConnectionPool
    let config: RipperConfig
    let meter: Meter
    let stats: EngineStats
    let auto: AutoConcurrency?
    let clock: MonotonicClock
    let logger: Logger
}

/// Bytes already held from the front of a piece; a retry or a backup copy asks only for the rest.
struct Prefix: Sendable {
    var bytes: Int64 = 0
    var chunks: [[UInt8]] = []
}

struct AttemptOutput: Sendable {
    let bytes: [UInt8]
    let total: Int64?
    let url: String
}

/// Live state of one copy of a piece, read by the watchdog and by hedging decisions.
final class AttemptProgress: @unchecked Sendable {
    struct State {
        var started = false
        var startedAt: Double = 0
        var gotHeaders = false
        var headersAt: Double = 0
        var lastProgressAt: Double = 0
        var base = Prefix()
        var received: Int64 = 0
        var chunks: [[UInt8]] = []
        var length: Int64 = 0
        var seenBytes: Int64 = 0
        var seenAt: Double = 0
        var failed = false
    }

    let state = Locked(State())

    func begin(at: Double, length: Int64, base: Prefix) {
        state.withLock { value in
            value.started = true
            value.startedAt = at
            value.lastProgressAt = at
            value.seenAt = at
            value.length = length
            value.base = base
        }
    }

    func headers(at: Double) {
        state.withLock { value in
            value.gotHeaders = true
            value.headersAt = at
            value.lastProgressAt = at
        }
    }

    func append(_ chunk: [UInt8], at: Double) {
        state.withLock { value in
            value.received += Int64(chunk.count)
            value.chunks.append(chunk)
            value.lastProgressAt = at
        }
    }

    func markFailed() { state.withLock { $0.failed = true } }
    var failed: Bool { state.withLock { $0.failed } }
    var isStarted: Bool { state.withLock { $0.started } }
    var received: Int64 { state.withLock { $0.received } }
    var headersAt: Double { state.withLock { $0.headersAt } }
    var timing: (gotHeaders: Bool, lastProgressAt: Double) { state.withLock { ($0.gotHeaders, $0.lastProgressAt) } }

    /// The resumed base plus this copy's bytes: the front of the piece this copy has made available.
    func prefix() -> Prefix {
        state.withLock { Prefix(bytes: $0.base.bytes + $0.received, chunks: $0.base.chunks + $0.chunks) }
    }
}

struct AttemptRunner: Sendable {
    let ctx: EngineContext

    /// One request for `piece` (or its missing tail) to `url`: waits for a connection, enforces
    /// BTR's three timeouts, checks the 206 Content-Range and the length, and reports the outcome to
    /// the resolver, meter, stats and automatic connection count.
    func run(url: String, piece: ByteRange, progress: AttemptProgress, resolver: Resolver, priority: Double,
             queueClass: QueueClass, deadline: (@Sendable () -> Double)?, resumeBase: @Sendable () -> Prefix) async throws -> AttemptOutput {
        let permit = try await ctx.pool.acquire(priority: priority, queueClass: queueClass, deadline: deadline)
        defer { permit.release() }
        try Task.checkCancellation()
        // Taken now, not when queued: a backup copy that waited resumes from what the first copy has by now.
        var base = resumeBase()
        if base.bytes >= piece.length { base = Prefix() }
        guard let part = ByteRange(start: piece.start + base.bytes, end: piece.end) else { throw RipperError.invalidURL }
        let started = ctx.clock.nowMs()
        progress.begin(at: started, length: part.length, base: base)
        let node = NodeCatalog.nodeKey(of: url)
        ctx.stats.started(node: node)
        do {
            let output = try await withThrowingTaskGroup(of: AttemptOutput?.self) { group -> AttemptOutput in
                group.addTask { try await self.transfer(url: url, part: part, base: base, progress: progress, started: started, node: node) }
                group.addTask {
                    try await self.watchdog(progress: progress, started: started)
                    return nil
                }
                while let result = try await group.next() {
                    if let output = result {
                        group.cancelAll()
                        return output
                    }
                }
                throw RipperError.closed
            }
            let elapsed = max(1, ctx.clock.nowMs() - started)
            ctx.meter.record(bytes: part.length, elapsedMs: elapsed)
            resolver.success(url, bps: part.length >= Meter.sampleMinBytes ? Double(part.length) * 1000 / elapsed : 0)
            ctx.logger.debug(.engine, "piece", ["node": .init(node), "range": .init(part.description),
                                                "firstByteMs": .init((progress.headersAt - started).rounded()),
                                                "bytes": .init(part.length), "ms": .init(elapsed.rounded()), "resumed": .init(base.bytes)])
            return output
        } catch {
            let received = progress.received
            let elapsed = max(1, ctx.clock.nowMs() - started)
            let cancelled = Task.isCancelled || error is CancellationError
            if cancelled {
                // A copy that lost the race still measured its node; without this a slow node is never measured.
                if received >= Meter.sampleMinBytes { resolver.sample(url, bps: Double(received) * 1000 / elapsed) }
            } else {
                let ripperError = error as? RipperError
                resolver.failure(url, status: ripperError?.status, receivedBytes: received)
                if let status = ripperError?.status, status == 412 || status == 429 {
                    ctx.auto?.pushback(status: status)
                } else if ripperError == .firstByteTimeout && received == 0 {
                    ctx.auto?.slow()
                }
                ctx.logger.debug(.engine, "attempt failed", ["node": .init(node), "error": .init(String(describing: error)),
                                                             "bytes": .init(received), "ms": .init(elapsed.rounded())])
            }
            ctx.stats.failed(node: node, wastedBytes: received, cancelled: cancelled)
            throw error
        }
    }

    private func transfer(url: String, part: ByteRange, base: Prefix, progress: AttemptProgress, started: Double, node: String) async throws -> AttemptOutput? {
        guard let target = URL(string: url) else { throw RipperError.invalidURL }
        let response = try await ctx.transport.fetch(target, range: part)
        let now = ctx.clock.nowMs()
        progress.headers(at: now)
        ctx.stats.firstByte(node: node, ms: now - started)
        let contentRange = ContentRange.parse(response.headers["content-range"])
        guard response.status == 206, let contentRange, contentRange.range == part else {
            throw RipperError.badResponse(status: response.status)
        }
        for try await chunk in response.body {
            try Task.checkCancellation()
            progress.append(chunk, at: ctx.clock.nowMs())
            ctx.auto?.activity()
        }
        // A cancelled body simply ends; that is not a short response.
        try Task.checkCancellation()
        let got = progress.received
        guard got == part.length else { throw RipperError.lengthMismatch(got: got, expected: part.length) }
        let whole = progress.prefix()
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(whole.bytes))
        for chunk in whole.chunks { bytes += chunk }
        return AttemptOutput(bytes: bytes, total: contentRange.total, url: url)
    }

    private func watchdog(progress: AttemptProgress, started: Double) async throws {
        while true {
            try await sleepMs(25)
            let timing = progress.timing
            let now = ctx.clock.nowMs()
            if !timing.gotHeaders && now - started > ctx.config.firstByteTimeoutMs { throw RipperError.firstByteTimeout }
            if timing.gotHeaders && now - timing.lastProgressAt > ctx.config.stallTimeoutMs { throw RipperError.stalled }
            if now - started > ctx.config.attemptTimeoutMs { throw RipperError.attemptTimeout }
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter AttemptTests`
Expected: 5 tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Ripper attempt runner, transport contract and simulated CDN"
```

---

### Task 18: Ripper part 7, piece downloads with hedging, primary assignment and ordered range streaming

**Files:**
- Create: `Sources/Ripper/PieceDownloader.swift`, `Sources/Ripper/PrimaryAssigner.swift`, `Sources/Ripper/RangeDownloader.swift`
- Test: `Tests/RipperTests/PrimaryAssignerTests.swift`, `Tests/RipperTests/RangeDownloaderTests.swift`

**Interfaces:**
- Consumes: everything from Task 17.
- Produces (internal, used by Task 19):
  - `enum PieceMode { case normal, startup, probe }` with `queueClass`.
  - `PieceDownloader(ctx:)` with `runner` and `download(piece:index:resolver:preferred:mode:priority:deadline:) async throws -> AttemptOutput`.
  - `PrimaryAssigner().assign(urls:count:speed:trialKey:) -> [String]`.
  - `RangeDownloader(ctx:)` with `meta(_ range:resolver:) async throws -> AttemptOutput` and `stream(_ range:resolver:startup:priority:deadline:) -> AsyncThrowingStream<[UInt8], Error>` (bytes in file order).

Ported from BTR `downloadPiece` (rounds, pairs, backup copies, prefix resume), `hedgeDue`, `pieceCandidates`, `assignPrimaries`, `downloadStartupRange`, `downloadStartupMediaRange` and `downloadRange`. Left out on purpose: the early-hedge rescue budgets (`createEarlyHedge`), the separate audio/video connection budgets of the startup range, and the spec's hurry mode (section 8, deferred); add them only if the phone logs show slow first segments or seeks.

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/PrimaryAssignerTests.swift`:

```swift
import XCTest
@testable import Ripper

final class PrimaryAssignerTests: XCTestCase {
    final class Key {}

    func testWeightedTurnsAndTrialsAtTheEnd() {
        let speeds = ["A": 10.0, "B": 5.0, "C": 0.0]
        let result = PrimaryAssigner().assign(urls: ["A", "B", "C"], count: 8, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key()))
        XCTAssertEqual(result, ["A", "B", "A", "A", "B", "A", "C", "C"])
    }

    func testVerySlowNodeGetsNothing() {
        let speeds = ["A": 120.0, "B": 5.0]
        XCTAssertEqual(PrimaryAssigner().assign(urls: ["A", "B"], count: 4, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(Key())),
                       ["A", "A", "A", "A"])
    }

    func testRoundRobinWithoutMeasurementsRotatesPerRange() {
        let assigner = PrimaryAssigner()
        let key = ObjectIdentifier(Key())
        XCTAssertEqual(assigner.assign(urls: ["a", "b", "c"], count: 4, speed: { _ in 0 }, trialKey: key), ["a", "b", "c", "a"])
        XCTAssertEqual(assigner.assign(urls: ["a", "b", "c"], count: 4, speed: { _ in 0 }, trialKey: key), ["b", "c", "a", "b"])
    }

    func testSmallRangesGiveAnUnknownNodeATrialEveryFourth() {
        let assigner = PrimaryAssigner()
        let owner = Key()
        let speeds = ["A": 10.0]
        var results: [[String]] = []
        for _ in 0..<4 {
            results.append(assigner.assign(urls: ["A", "C"], count: 2, speed: { speeds[$0] ?? 0 }, trialKey: ObjectIdentifier(owner)))
        }
        XCTAssertEqual(results, [["A", "A"], ["A", "A"], ["A", "A"], ["A", "C"]])
    }
}
```

`Tests/RipperTests/RangeDownloaderTests.swift`:

```swift
import XCTest
import BiliShared
@testable import Ripper

final class RangeDownloaderTests: XCTestCase {
    let mebibyte = ByteRange(start: 0, end: 1_048_575)!

    func collect(_ cdn: SimCDN, range: ByteRange, resolver: Resolver = TestEngine.resolver(), startup: Bool = false,
                 auto: AutoConcurrency? = nil, config: RipperConfig = TestEngine.config) async throws -> [UInt8] {
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn, config: config, auto: auto))
        var bytes: [UInt8] = []
        for try await chunk in downloader.stream(range, resolver: resolver, startup: startup, priority: 50, deadline: nil) {
            bytes += chunk
        }
        return bytes
    }

    func testAllFastNodesDeliverExactBytesInOrder() async throws {
        let cdn = SimCDN(size: 2_000_000)
        let bytes = try await collect(cdn, range: mebibyte)
        XCTAssertEqual(bytes, Array(cdn.content[0...1_048_575]))
        XCTAssertGreaterThan(Set(cdn.requests.current).count, 1, "pieces should spread over several nodes")
    }

    func testStartupProbeThenPieces() async throws {
        let cdn = SimCDN(size: 2_000_000)
        let range = ByteRange(start: 1_000, end: 900_000)!
        XCTAssertEqual(try await collect(cdn, range: range, startup: true), Array(cdn.content[1_000...900_000]))
    }

    func testRefusingNodeIsRoutedAroundAndBanned() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(status: 403)])
        let resolver = TestEngine.resolver()
        XCTAssertEqual(try await collect(cdn, range: mebibyte, resolver: resolver), Array(cdn.content[0...1_048_575]))
        let cosovURL = TestEngine.primary.replacingOccurrences(of: "upos-sz-mirrorcos.bilivideo.com", with: TestEngine.cosov)
        XCTAssertFalse(resolver.allows(cosovURL))
    }

    func testBrokenNodesNeverCorruptTheOutput() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [
            TestEngine.cosov: .init(wrongRange: true),
            TestEngine.aliov: .init(truncateAfter: 10_000),
            TestEngine.hk1: .init(stallAfter: 16_384),
        ])
        XCTAssertEqual(try await collect(cdn, range: mebibyte), Array(cdn.content[0...1_048_575]))
    }

    func testSlowFirstByteIsHedged() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 1_000)])
        let started = Date()
        XCTAssertEqual(try await collect(cdn, range: mebibyte), Array(cdn.content[0...1_048_575]))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testEveryNodeRefusingFails() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 403) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        do {
            _ = try await collect(cdn, range: ByteRange(start: 0, end: 99_999)!)
            XCTFail("expected a failure")
        } catch {
            XCTAssertNotNil(error as? RipperError)
        }
    }

    /// Review focus 5: a Wi-Fi to cellular switch makes every node fail for a moment.
    func testShortNetworkBlipIsRiddenOut() async throws {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(failForMs: 400) }
        let cdn = SimCDN(size: 2_000_000, behaviors: behaviors)
        XCTAssertEqual(try await collect(cdn, range: ByteRange(start: 0, end: 299_999)!), Array(cdn.content[0...299_999]))
    }

    func testRateLimitPushesConnectionsDown() async throws {
        let cdn = SimCDN(size: 2_000_000, behaviors: [TestEngine.aliov: .init(status: 429)])
        let auto = AutoConcurrency()
        auto.newSession()
        XCTAssertEqual(auto.threads, 16)
        var config = TestEngine.config
        config.fixedConcurrency = nil
        _ = try await collect(cdn, range: mebibyte, auto: auto, config: config)
        XCTAssertLessThan(auto.threads, 16)
    }

    func testMetaRaceReturnsTheWholeRange() async throws {
        let cdn = SimCDN(size: 50_000, behaviors: [TestEngine.cosov: .init(firstByteMs: 200)])
        let downloader = RangeDownloader(ctx: TestEngine.context(cdn))
        let output = try await downloader.meta(ByteRange(start: 0, end: 4_999)!, resolver: TestEngine.resolver())
        XCTAssertEqual(output.bytes, Array(cdn.content[0..<5_000]))
        XCTAssertEqual(output.total, 50_000)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter "PrimaryAssignerTests|RangeDownloaderTests"`
Expected: compile errors.

- [ ] **Step 3: Implement primary assignment**

`Sources/Ripper/PrimaryAssigner.swift`:

```swift
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
```

- [ ] **Step 4: Implement the piece downloader**

`Sources/Ripper/PieceDownloader.swift`:

```swift
import Foundation
import BiliShared

enum PieceMode: Sendable {
    case normal
    /// The first segment of a playback or after a seek.
    case startup
    /// The first small piece of a startup range, raced over many nodes at once.
    case probe

    var queueClass: QueueClass {
        switch self {
        case .probe: return .critical
        case .startup: return .startup
        case .normal: return .ordinary
        }
    }
}

final class PieceDownloader: @unchecked Sendable {
    static let resumeMinBytes: Int64 = 32 * 1024

    let ctx: EngineContext
    let runner: AttemptRunner

    init(ctx: EngineContext) {
        self.ctx = ctx
        runner = AttemptRunner(ctx: ctx)
    }

    /// One piece, in up to `pieceRounds` rounds. Each round walks the candidates two at a time: the
    /// first copy starts at once, the backup copy once the first is late (see `hedgeDue`); the first
    /// to finish wins and the other is cancelled. Bytes already received survive into the next try.
    func download(piece: ByteRange, index: Int, resolver: Resolver, preferred: [String], mode: PieceMode, priority: Double,
                  deadline: (@Sendable () -> Double)?) async throws -> AttemptOutput {
        let started = ctx.clock.nowMs()
        let prefix = Locked(Prefix())
        var lastError: Error = RipperError.noNodes
        for round in 0..<ctx.config.pieceRounds {
            if round > 0 {
                if ctx.clock.nowMs() - started > ctx.config.retryWindowMs { break }
                try await sleepMs(min(2_000, 500 * pow(2, Double(round - 1))))
            }
            let candidates = Self.candidates(preferred: preferred, resolver: resolver, pieceIndex: index, round: round)
            let limit = min(8, candidates.count)
            let width = mode == .probe ? limit : 2
            var tried = Set<String>()
            while tried.count < limit {
                try Task.checkCancellation()
                let untried = candidates.filter { !tried.contains($0) }
                let open = untried.filter(resolver.allows)
                let pair = Array((open.isEmpty ? untried : open).prefix(width))
                if pair.isEmpty { break }
                pair.forEach { tried.insert($0) }
                do {
                    let output = try await race(pair, piece: piece, resolver: resolver, mode: mode, priority: priority,
                                                deadline: deadline, prefix: prefix)
                    ctx.auto?.delivered(piece.length)
                    ctx.stats.delivered(piece.length)
                    return output
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastError = error
                }
            }
        }
        throw lastError
    }

    private func race(_ pair: [String], piece: ByteRange, resolver: Resolver, mode: PieceMode, priority: Double,
                      deadline: (@Sendable () -> Double)?, prefix: Locked<Prefix>) async throws -> AttemptOutput {
        let first = AttemptProgress()
        let hasDeadline = deadline.map { $0().isFinite } ?? false
        return try await withThrowingTaskGroup(of: AttemptOutput.self) { group -> AttemptOutput in
            for (position, url) in pair.enumerated() {
                group.addTask {
                    let progress = position == 0 ? first : AttemptProgress()
                    if position > 0 {
                        try await self.waitForCopy(first: first, copyURL: url, resolver: resolver, mode: mode,
                                                   hasDeadline: hasDeadline, deadline: deadline)
                    }
                    do {
                        return try await self.runner.run(
                            url: url, piece: piece, progress: progress, resolver: resolver,
                            priority: priority + (position > 0 ? 20 : 0), queueClass: mode.queueClass, deadline: deadline,
                            resumeBase: { Self.resumeBase(prefix: prefix.current, live: position > 0 ? first.prefix() : nil, pieceLength: piece.length) })
                    } catch {
                        let kept = progress.prefix()
                        if kept.bytes < piece.length {
                            prefix.withLock { if kept.bytes > $0.bytes { $0 = kept } }
                        }
                        if position == 0 { first.markFailed() }
                        throw error
                    }
                }
            }
            var lastError: Error = RipperError.noNodes
            while true {
                do {
                    guard let output = try await group.next() else { break }
                    group.cancelAll()
                    return output
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }
    }

    static func resumeBase(prefix: Prefix, live: Prefix?, pieceLength: Int64) -> Prefix {
        var base = prefix.bytes >= resumeMinBytes ? prefix : Prefix()
        if let live, live.bytes >= resumeMinBytes, live.bytes > base.bytes { base = live }
        return base.bytes >= pieceLength ? Prefix() : base
    }

    private func waitForCopy(first: AttemptProgress, copyURL: String, resolver: Resolver, mode: PieceMode,
                             hasDeadline: Bool, deadline: (@Sendable () -> Double)?) async throws {
        if mode == .probe { return }
        let measured = ctx.meter.hedgeDelayMs(configured: ctx.config.hedgeDelayMs)
        let delay = mode == .startup ? min(hasDeadline ? 200 : 250, measured) : measured
        let waitStarted = ctx.clock.nowMs()
        while true {
            if first.failed { return }
            if hasDeadline, let deadline {
                if first.isStarted && hedgeDue(first: first, delayMs: delay, deadlineAt: deadline(), copyBps: resolver.speed(copyURL)) { return }
            } else if ctx.clock.nowMs() - waitStarted >= delay {
                return
            }
            try await sleepMs(50)
        }
    }

    /// BTR `hedgeDue`, without the rescue budgets.
    func hedgeDue(first: AttemptProgress, delayMs: Double, deadlineAt: Double, copyBps: Double) -> Bool {
        let now = ctx.clock.nowMs()
        let usual = ctx.meter.connectionBps
        return first.state.withLock { value in
            let ran = now - value.startedAt
            if value.received != value.seenBytes {
                value.seenBytes = value.received
                value.seenAt = now
            }
            if ran < delayMs { return false }
            if value.received == 0 || now - value.seenAt >= delayMs { return true }
            let rate = Double(value.received) * 1000 / ran
            let remaining = Double(max(0, value.length - value.received))
            if now + remaining * 1000 / rate <= deadlineAt - 1_500 { return false }
            if copyBps > rate * 1.5 { return true }
            if !(usual > 0) || rate < usual * 0.6 { return true }
            return !(copyBps > 0)
        }
    }

    /// BTR `pieceCandidates`: the assigned node first, then the fastest known nodes.
    static func candidates(preferred: [String], resolver: Resolver, pieceIndex: Int, round: Int) -> [String] {
        let offset = preferred.isEmpty ? 0 : round % preferred.count
        let rotated = Array(preferred[offset...] + preferred[..<offset])
        let rescue = resolver.rescueCandidates().filter { !rotated.contains($0) }
        let rest = (Array(rotated.dropFirst()) + rescue).sorted { resolver.speed($0) > resolver.speed($1) }
        var list = rotated.isEmpty ? rest : [rotated[0]] + rest
        for url in resolver.ordered(pieceIndex: pieceIndex) where !list.contains(url) {
            list.append(url)
        }
        return list
    }
}
```

- [ ] **Step 5: Implement the range downloader**

`Sources/Ripper/RangeDownloader.swift`:

```swift
import Foundation
import BiliShared

final class RangeDownloader: @unchecked Sendable {
    let ctx: EngineContext
    let pieces: PieceDownloader
    let assigner = PrimaryAssigner()

    init(ctx: EngineContext) {
        self.ctx = ctx
        pieces = PieceDownloader(ctx: ctx)
    }

    /// BTR `downloadStartupRange`: init and index in one request, raced over up to three nodes
    /// started 0, 120 and 300 ms apart; rounds as for pieces.
    func meta(_ range: ByteRange, resolver: Resolver) async throws -> AttemptOutput {
        let started = ctx.clock.nowMs()
        var lastError: Error = RipperError.noNodes
        for round in 0..<ctx.config.pieceRounds {
            if round > 0 {
                if ctx.clock.nowMs() - started > ctx.config.retryWindowMs { break }
                try await sleepMs(min(2_000, 500 * pow(2, Double(round - 1))))
            }
            var candidates = Array(resolver.startupCandidates().prefix(3))
            if candidates.isEmpty && round > 0 { candidates = Array(resolver.ordered(pieceIndex: round).prefix(3)) }
            if candidates.isEmpty { break }
            do {
                return try await withThrowingTaskGroup(of: AttemptOutput.self) { group -> AttemptOutput in
                    let delays: [Double] = [0, 120, 300]
                    for (index, url) in candidates.enumerated() {
                        group.addTask {
                            try await sleepMs(delays[index])
                            return try await self.pieces.runner.run(url: url, piece: range, progress: AttemptProgress(), resolver: resolver,
                                                                    priority: 220, queueClass: .critical, deadline: nil, resumeBase: { Prefix() })
                        }
                    }
                    var last: Error = RipperError.noNodes
                    while true {
                        do {
                            guard let output = try await group.next() else { break }
                            group.cancelAll()
                            return output
                        } catch {
                            last = error
                        }
                    }
                    throw last
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    /// The bytes of `range` in file order, each piece yielded as soon as it and all before it are in.
    func stream(_ range: ByteRange, resolver: Resolver, startup: Bool, priority: Double,
                deadline: (@Sendable () -> Double)?) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(range, resolver: resolver, startup: startup, priority: priority, deadline: deadline) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ range: ByteRange, resolver: Resolver, startup: Bool, priority: Double,
                     deadline: (@Sendable () -> Double)?, emit: @escaping @Sendable ([UInt8]) -> Void) async throws {
        var totals: [Int64] = []
        var preferred = resolver.rangeCandidates()
        var assignable = preferred
        var remaining = range
        var indexOffset = 0
        if startup {
            // A small head piece raced over every candidate measures the nodes and gets the first bytes
            // to the player fast; the rest is then spread over the nodes that proved themselves.
            let headLength = min(range.length, max(64 * 1024, ctx.config.minChunkBytes))
            guard let head = ByteRange(start: range.start, end: range.start + headLength - 1) else { return }
            let result = try await pieces.download(piece: head, index: 0, resolver: resolver, preferred: preferred, mode: .probe,
                                                   priority: 220, deadline: deadline)
            emit(result.bytes)
            if let total = result.total { totals.append(total) }
            guard head.end < range.end, let rest = ByteRange(start: head.end + 1, end: range.end) else { return }
            remaining = rest
            preferred = [result.url] + preferred.filter { $0 != result.url }
            assignable = preferred.filter { $0 == result.url || resolver.speed($0) > 0 }
            indexOffset = 1
        }
        let concurrency = ctx.pool.limit
        let rescueReserve = concurrency >= 8 ? min(8, max(1, (concurrency + 7) / 8)) : 0
        let pieceConcurrency = max(1, concurrency - rescueReserve)
        let minChunk = ctx.meter.adaptiveMinChunk(base: ctx.config.minChunkBytes, rangeLength: remaining.length,
                                                  pieceLimit: pieceConcurrency, hostCount: preferred.count)
        let parts = remaining.split(concurrency: pieceConcurrency, minChunk: minChunk)
        let primaries = assigner.assign(urls: assignable, count: parts.count, speed: resolver.speed, trialKey: ObjectIdentifier(resolver))
        let mode: PieceMode = startup ? .startup : .normal
        let order = preferred
        try await withThrowingTaskGroup(of: (Int, AttemptOutput).self) { group in
            for (offset, part) in parts.enumerated() {
                let primary = offset < primaries.count ? primaries[offset] : order.first
                let piecePreferred = primary.map { first in [first] + order.filter { $0 != first } } ?? order
                let pieceIndex = offset + indexOffset
                let piecePriority = startup ? 120 - Double(min(30, pieceIndex)) : priority - Double(min(20, pieceIndex))
                group.addTask {
                    let output = try await self.pieces.download(piece: part, index: pieceIndex, resolver: resolver, preferred: piecePreferred,
                                                                mode: mode, priority: piecePriority, deadline: deadline)
                    return (offset, output)
                }
            }
            var ready: [Int: AttemptOutput] = [:]
            var next = 0
            for try await (offset, output) in group {
                ready[offset] = output
                while let item = ready.removeValue(forKey: next) {
                    emit(item.bytes)
                    if let total = item.total { totals.append(total) }
                    next += 1
                }
            }
        }
        if let first = totals.first, totals.contains(where: { $0 != first }) {
            throw RipperError.totalMismatch
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter "PrimaryAssignerTests|RangeDownloaderTests"`
Expected: all pass. Run the RangeDownloader tests 5 times in a row; they use real time and must not be flaky. If one is, widen that test's timing margin, never the engine's rules.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add piece hedging, primary assignment and ordered range streaming (BTR downloader port)"
```

---

### Task 19: Ripper part 8, playback session with deadlines and prefetch

**Files:**
- Create: `Sources/Ripper/RipperSession.swift`
- Test: `Tests/RipperTests/RipperSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 12-18; `MediaSegment` (BiliShared); `Logger`.
- Produces: `enum TrackKind: String { case video, audio }`; `TrackHeaders` (`bytes`, `totalSize`); `RipperSession(sources:mode:config:transport:auto:policy:clock:logger:)` where `sources: [TrackKind: (primary: String, backups: [String])]`, with `loadHeaders(_:through:) async throws -> TrackHeaders`, `setSegments(_:_:)`, `read(_:_:) -> AsyncThrowingStream<[UInt8], Error>`, `updatePlayhead(seconds:rate:)`, `reportBuffer(aheadSeconds:playing:)`, `reportStall()`, `replaceURLs(_:primary:backups:)`, `dropCache()`, `stats() -> RipperStats`, `onFatal: ((Error) -> Void)?`, `close()`.

Behaviour: a request whose start is not right after the track's previous one is a seek, which cancels that track's prefetches, restarts the automatic connection count's startup boost and is fetched in startup mode. After each served segment the session prefetches the following segments of that track, up to 45 s ahead of the playhead and 64 MB (video) / 8 MB (audio), at priority 10. A player request that fails after every retry calls `onFatal`; prefetch failures are only logged.

- [ ] **Step 1: Write the failing tests**

`Tests/RipperTests/RipperSessionTests.swift`:

```swift
import XCTest
import BiliShared
import DevLog
@testable import Ripper

final class RipperSessionTests: XCTestCase {
    let size = 4 * 1024 * 1024
    let headerEnd: Int64 = 1_023

    func segments() -> [MediaSegment] {
        (0..<12).map { index in
            let start = headerEnd + 1 + Int64(index) * 262_144
            return MediaSegment(index: index, range: ByteRange(start: start, end: start + 262_143)!, startTime: Double(index) * 2, duration: 2)
        }
    }

    func makeSession(_ cdn: SimCDN) -> RipperSession {
        RipperSession(sources: [.video: (TestEngine.primary, [])], mode: .overseas, config: TestEngine.config,
                      transport: cdn, auto: nil, logger: Logger(session: "test"))
    }

    func read(_ session: RipperSession, _ range: ByteRange) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for try await chunk in session.read(.video, range) { bytes += chunk }
        return bytes
    }

    func testHeadersSegmentsAndPrefetch() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        let headers = try await session.loadHeaders(.video, through: headerEnd)
        XCTAssertEqual(headers.bytes, Array(cdn.content[0...1_023]))
        XCTAssertEqual(headers.totalSize, Int64(size))
        session.setSegments(.video, segments())
        let first = segments()[0].range
        XCTAssertEqual(try await read(session, first), Array(cdn.content[Int(first.start)...Int(first.end)]))
        try await Task.sleep(nanoseconds: 500_000_000)
        let second = segments()[1].range
        XCTAssertEqual(try await read(session, second), Array(cdn.content[Int(second.start)...Int(second.end)]))
        XCTAssertGreaterThanOrEqual(session.stats().cacheHits, 1)
        session.close()
    }

    func testHeaderBytesAreServedFromMemory() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        _ = try await session.loadHeaders(.video, through: headerEnd)
        let before = cdn.requestCount()
        XCTAssertEqual(try await read(session, ByteRange(start: 0, end: 99)!), Array(cdn.content[0...99]))
        XCTAssertEqual(cdn.requestCount(), before)
    }

    func testSeekAndUnalignedRanges() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        session.setSegments(.video, segments())
        let late = segments()[9].range
        XCTAssertEqual(try await read(session, late), Array(cdn.content[Int(late.start)...Int(late.end)]))
        let odd = ByteRange(start: 5_000, end: 70_000)!
        XCTAssertEqual(try await read(session, odd), Array(cdn.content[5_000...70_000]))
    }

    func testFatalWhenEveryNodeRefuses() async {
        var behaviors: [String: SimCDN.Behavior] = [:]
        for node in NodeCatalog.overseas { behaviors[node] = .init(status: 403) }
        let session = makeSession(SimCDN(size: size, behaviors: behaviors))
        let fatal = Locked(false)
        session.onFatal = { _ in fatal.withLock { $0 = true } }
        do {
            _ = try await read(session, ByteRange(start: 2_000, end: 50_000)!)
            XCTFail("expected a failure")
        } catch {}
        XCTAssertTrue(fatal.current)
    }

    func testClosedSessionRefusesReads() async {
        let session = makeSession(SimCDN(size: size))
        session.close()
        do {
            _ = try await read(session, ByteRange(start: 2_000, end: 3_000)!)
            XCTFail("expected closed")
        } catch {
            XCTAssertEqual(error as? RipperError, .closed)
        }
    }

    func testReplacedURLsKeepWorking() async throws {
        let cdn = SimCDN(size: size)
        let session = makeSession(cdn)
        session.replaceURLs(.video, primary: TestEngine.primary.replacingOccurrences(of: "deadline=9", with: "deadline=99"), backups: [])
        let range = ByteRange(start: 2_000, end: 80_000)!
        XCTAssertEqual(try await read(session, range), Array(cdn.content[2_000...80_000]))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter RipperSessionTests`
Expected: compile errors.

- [ ] **Step 3: Implement the session**

`Sources/Ripper/RipperSession.swift`:

```swift
import Foundation
import BiliShared
import DevLog

public enum TrackKind: String, Sendable, Hashable, CaseIterable {
    case video, audio
}

public struct TrackHeaders: Sendable {
    /// Bytes 0 through the end of the SIDX: init segment plus index.
    public let bytes: [UInt8]
    public let totalSize: Int64
}

/// One playback: both tracks' resolvers, the shared connection pool, the segment cache and prefetch.
public final class RipperSession: @unchecked Sendable {
    private struct CacheKey: Hashable {
        let track: TrackKind
        let range: ByteRange
    }

    private struct State {
        var headers: [TrackKind: TrackHeaders] = [:]
        var segments: [TrackKind: [MediaSegment]] = [:]
        var cache: [CacheKey: [UInt8]] = [:]
        var inflight: [CacheKey: Task<[UInt8], Error>] = [:]
        var lastServedEnd: [TrackKind: Int64] = [:]
        var playhead: Double = 0
        var rate: Double = 1
        var closed = false
        var reads = 0
    }

    private let state = Locked(State())
    private let resolvers: [TrackKind: Resolver]
    private let downloader: RangeDownloader
    private let ctx: EngineContext
    private let bans = BanList()
    public var onFatal: ((Error) -> Void)?

    public init(sources: [TrackKind: (primary: String, backups: [String])], mode: NodeMode, config: RipperConfig = RipperConfig(),
                transport: RangeTransport, auto: AutoConcurrency?, policy: MediaURLPolicy = .bilibili,
                clock: MonotonicClock = .system, logger: Logger = .shared) {
        let follower = config.fixedConcurrency == nil ? auto : nil
        let pool = ConnectionPool(limit: config.fixedConcurrency ?? follower?.threads ?? 16, clock: clock)
        ctx = EngineContext(transport: transport, pool: pool, config: config, meter: Meter(), stats: EngineStats(),
                            auto: follower, clock: clock, logger: logger)
        var resolvers: [TrackKind: Resolver] = [:]
        for (kind, source) in sources {
            resolvers[kind] = Resolver(primary: source.primary, backups: source.backups, mode: mode, policy: policy, bans: bans, clock: clock)
        }
        self.resolvers = resolvers
        downloader = RangeDownloader(ctx: ctx)
        bans.onBan = { node, strikes, kind in
            logger.warn(.engine, "ban", ["node": .init(node), "strikes": .init(strikes), "kind": .init(String(describing: kind))])
        }
        if let follower {
            pool.onChange = { active, limit, queued in follower.demand(active: active, limit: limit, queued: queued) }
            follower.onChange = { [weak pool] threads, previous, reason in
                pool?.setLimit(threads)
                logger.info(.engine, "threads", ["threads": .init(threads), "previous": .init(previous), "reason": .init(reason)])
            }
            follower.newSession()
            pool.setLimit(follower.threads)
        }
    }

    public func loadHeaders(_ track: TrackKind, through indexEnd: Int64) async throws -> TrackHeaders {
        guard let resolver = resolvers[track], let range = ByteRange(start: 0, end: indexEnd) else { throw RipperError.noNodes }
        let output = try await downloader.meta(range, resolver: resolver)
        guard let total = output.total else { throw RipperError.badResponse(status: 206) }
        let headers = TrackHeaders(bytes: output.bytes, totalSize: total)
        state.withLock { $0.headers[track] = headers }
        ctx.logger.info(.engine, "headers", ["track": .init(track.rawValue), "bytes": .init(Int64(output.bytes.count)),
                                             "node": .init(NodeCatalog.nodeKey(of: output.url))])
        return headers
    }

    public func setSegments(_ track: TrackKind, _ segments: [MediaSegment]) {
        state.withLock { $0.segments[track] = segments }
    }

    public func read(_ track: TrackKind, _ range: ByteRange) -> AsyncThrowingStream<[UInt8], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.serve(track, range) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func updatePlayhead(seconds: Double, rate: Double) {
        state.withLock { value in
            value.playhead = seconds
            value.rate = rate > 0 ? rate : 1
            let behind = value.cache.keys.filter { key in
                guard let segment = value.segments[key.track]?.first(where: { $0.range == key.range }) else { return false }
                return segment.endTime < seconds - 2
            }
            for key in behind { value.cache[key] = nil }
        }
    }

    public func reportBuffer(aheadSeconds: Double, playing: Bool) {
        ctx.auto?.buffer(ahead: aheadSeconds, playing: playing)
    }

    public func reportStall() {
        ctx.auto?.stall()
    }

    public func replaceURLs(_ track: TrackKind, primary: String, backups: [String]) {
        resolvers[track]?.replaceURLs(primary: primary, backups: backups)
        ctx.logger.info(.engine, "urls replaced", ["track": .init(track.rawValue), "url": .init(primary)])
    }

    public func dropCache() {
        state.withLock { $0.cache.removeAll() }
    }

    public func stats() -> RipperStats {
        var stats = ctx.stats.snapshot()
        stats.concurrency = ctx.pool.limit
        stats.nodeStates = resolvers[.video]?.status() ?? []
        return stats
    }

    public func close() {
        let tasks = state.withLock { value -> [Task<[UInt8], Error>] in
            value.closed = true
            value.cache.removeAll()
            defer { value.inflight.removeAll() }
            return Array(value.inflight.values)
        }
        tasks.forEach { $0.cancel() }
    }

    private enum Plan {
        case memory([UInt8])
        case inflight(Task<[UInt8], Error>)
        case fetch(seek: Bool)
    }

    private func serve(_ track: TrackKind, _ range: ByteRange, emit: @escaping @Sendable ([UInt8]) -> Void) async throws {
        guard let resolver = resolvers[track] else { throw RipperError.noNodes }
        let began = ctx.clock.nowMs()
        let key = CacheKey(track: track, range: range)
        let (plan, segment, isFirstRead) = try state.withLock { value -> (Plan, MediaSegment?, Bool) in
            guard !value.closed else { throw RipperError.closed }
            let segment = value.segments[track]?.first { $0.range.start == range.start }
            if let headers = value.headers[track], range.end < Int64(headers.bytes.count) {
                return (.memory(Array(headers.bytes[Int(range.start)...Int(range.end)])), segment, false)
            }
            if let bytes = value.cache.removeValue(forKey: key) { return (.memory(bytes), segment, false) }
            if let task = value.inflight[key] { return (.inflight(task), segment, false) }
            let seek = value.lastServedEnd[track].map { $0 + 1 != range.start } ?? true
            return (.fetch(seek: seek), segment, value.reads == 0)
        }
        var served = false
        var source = "fetch"
        switch plan {
        case .memory(let bytes):
            ctx.stats.cache(hit: true)
            emit(bytes)
            served = true
            source = "memory"
        case .inflight(let task):
            if let bytes = try? await task.value {
                ctx.stats.cache(hit: true)
                emit(bytes)
                served = true
                source = "prefetch"
            } else {
                try Task.checkCancellation()
            }
        case .fetch:
            break
        }
        if !served {
            ctx.stats.cache(hit: false)
            var seek = true
            if case .fetch(let isSeek) = plan { seek = isSeek }
            if seek {
                cancelPrefetch(track)
                if !isFirstRead { ctx.auto?.newSession() }
            }
            do {
                for try await chunk in downloader.stream(range, resolver: resolver, startup: seek, priority: ctx.config.priority,
                                                         deadline: deadline(for: segment)) {
                    emit(chunk)
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) {
                    ctx.logger.error(.engine, "range failed", ["track": .init(track.rawValue), "range": .init(range.description),
                                                               "error": .init(String(describing: error))])
                    onFatal?(error)
                }
                throw error
            }
        }
        ctx.logger.debug(.engine, "read", ["track": .init(track.rawValue), "range": .init(range.description), "source": .init(source),
                                           "ms": .init((ctx.clock.nowMs() - began).rounded())])
        state.withLock { value in
            value.lastServedEnd[track] = range.end
            value.reads += 1
        }
        schedulePrefetch(track, after: segment)
    }

    /// When playback needs this segment, as a monotonic time in ms; re-read on every queue pass.
    private func deadline(for segment: MediaSegment?) -> (@Sendable () -> Double)? {
        guard let segment else { return nil }
        let clock = ctx.clock
        return { [weak self] in
            guard let self else { return .infinity }
            let (playhead, rate) = self.state.withLock { ($0.playhead, $0.rate) }
            return clock.nowMs() + max(0, segment.startTime - playhead) / rate * 1000
        }
    }

    private func cancelPrefetch(_ track: TrackKind) {
        let tasks = state.withLock { value -> [Task<[UInt8], Error>] in
            let keys = value.inflight.keys.filter { $0.track == track }
            return keys.compactMap { value.inflight.removeValue(forKey: $0) }
        }
        tasks.forEach { $0.cancel() }
    }

    private func schedulePrefetch(_ track: TrackKind, after segment: MediaSegment?) {
        guard let segment, let resolver = resolvers[track] else { return }
        let cap = track == .video ? ctx.config.prefetchVideoBytes : ctx.config.prefetchAudioBytes
        let aheadLimit = ctx.config.prefetchAheadSeconds
        state.withLock { value in
            guard !value.closed, let segments = value.segments[track] else { return }
            let cached = value.cache.filter { $0.key.track == track }.reduce(Int64(0)) { $0 + Int64($1.value.count) }
            let pending = value.inflight.keys.filter { $0.track == track }.reduce(Int64(0)) { $0 + $1.range.length }
            var budget = cap - cached - pending
            var index = segment.index + 1
            while index < segments.count {
                let next = segments[index]
                index += 1
                if next.startTime - value.playhead > aheadLimit { break }
                let key = CacheKey(track: track, range: next.range)
                if value.cache[key] != nil || value.inflight[key] != nil { continue }
                if next.range.length > budget { break }
                budget -= next.range.length
                let stream = downloader.stream(next.range, resolver: resolver, startup: false, priority: 10, deadline: deadline(for: next))
                let task = Task<[UInt8], Error> {
                    var bytes: [UInt8] = []
                    bytes.reserveCapacity(Int(next.range.length))
                    for try await chunk in stream { bytes += chunk }
                    return bytes
                }
                value.inflight[key] = task
                Task { [weak self] in
                    let result = await task.result
                    guard let self else { return }
                    self.state.withLock { value in
                        guard value.inflight[key] != nil else { return }
                        value.inflight[key] = nil
                        if case .success(let bytes) = result, !value.closed { value.cache[key] = bytes }
                    }
                    if case .failure(let error) = result, !(error is CancellationError) {
                        self.ctx.logger.warn(.engine, "prefetch failed", ["track": .init(track.rawValue), "error": .init(String(describing: error))])
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter RipperSessionTests`
Expected: 6 tests pass. Then the full suite, five times in a row, with no failures.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add Ripper playback session with deadlines and prefetch"
```

---

### Task 20: Real network transport and the PC speed test

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Ripper/URLSessionRangeTransport.swift`, `Sources/ripper-bench/Bench.swift`

**Interfaces:**
- Consumes: `RangeTransport` (Task 17), `BiliClient`, `TrackSelector`, `SidxParser`, `RipperSession`.
- Produces: `URLSessionRangeTransport(headers:maxConnectionsPerHost:)` (public; the app uses it with `BiliClient.mediaHeaders`); executable `ripper-bench`.

The transport has no unit test of its own: it needs real sockets. It is exercised by the bench (live, on the PC) and by the simulator integration test in Task 28 (against a local fake CDN).

- [ ] **Step 1: Register the executable**

In `Package.swift` add to `products:` `.executable(name: "ripper-bench", targets: ["ripper-bench"]),` and to `targets:`:

```swift
        .executableTarget(name: "ripper-bench", dependencies: ["BiliShared", "BiliAPI", "DashHLS", "Ripper", "DevLog"]),
```

- [ ] **Step 2: Implement the transport**

`Sources/Ripper/URLSessionRangeTransport.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BiliShared

/// Streams range responses through URLSession's delegate callbacks, which work the same with
/// Apple's Foundation and with swift-corelibs-foundation on Windows.
public final class URLSessionRangeTransport: NSObject, RangeTransport, URLSessionDataDelegate, @unchecked Sendable {
    private final class Handler {
        var response: CheckedContinuation<TransportResponse, Error>?
        let body: AsyncThrowingStream<[UInt8], Error>
        let bodyContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation

        init(response: CheckedContinuation<TransportResponse, Error>) {
            self.response = response
            let pair = AsyncThrowingStream<[UInt8], Error>.makeStream()
            body = pair.stream
            bodyContinuation = pair.continuation
        }
    }

    private let handlers = Locked<[Int: Handler]>([:])
    private let headers: [String: String]
    private var session: URLSession!

    public init(headers: [String: String] = [:], maxConnectionsPerHost: Int = 8) {
        self.headers = headers
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = maxConnectionsPerHost
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    public func fetch(_ url: URL, range: ByteRange) async throws -> TransportResponse {
        var request = URLRequest(url: url)
        request.setValue(range.headerValue, forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TransportResponse, Error>) in
                let handler = Handler(response: continuation)
                handler.bodyContinuation.onTermination = { _ in task.cancel() }
                handlers.withLock { $0[task.taskIdentifier] = handler }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            if let name = name as? String, let value = value as? String { headers[name.lowercased()] = value }
        }
        let ready = handlers.withLock { map -> (CheckedContinuation<TransportResponse, Error>, AsyncThrowingStream<[UInt8], Error>)? in
            guard let handler = map[dataTask.taskIdentifier], let continuation = handler.response else { return nil }
            handler.response = nil
            return (continuation, handler.body)
        }
        if let ready {
            ready.0.resume(returning: TransportResponse(status: http?.statusCode ?? 0, headers: headers, body: ready.1))
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let handler = handlers.withLock { $0[dataTask.taskIdentifier] }
        handler?.bodyContinuation.yield([UInt8](data))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let finished = handlers.withLock { map -> (Handler, CheckedContinuation<TransportResponse, Error>?)? in
            guard let handler = map.removeValue(forKey: task.taskIdentifier) else { return nil }
            let pending = handler.response
            handler.response = nil
            return (handler, pending)
        }
        guard let finished else { return }
        let (handler, pending) = finished
        if let pending {
            pending.resume(throwing: error ?? RipperError.badResponse(status: 0))
        } else if let error {
            handler.bodyContinuation.finish(throwing: error)
        } else {
            handler.bodyContinuation.finish()
        }
    }
}
```

- [ ] **Step 3: Implement the bench**

`Sources/ripper-bench/Bench.swift`:

```swift
import Foundation
import BiliShared
import BiliAPI
import DashHLS
import DevLog
import Ripper

/// Downloads the start of a real video twice, over one connection and through Ripper, and prints both.
/// Usage: ripper-bench --bv BV1xxxxxxxxx [--cookies path] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc]
///        ripper-bench --playurl saved-playurl.json [same options]
@main
struct Bench {
    struct Options {
        var bvid: String?
        var cookies: String?
        var playurl: String?
        var megabytes = 16
        var mode = NodeMode.overseas
        var quality = 80
        var codec = VideoCodec.hevc
    }

    struct UsageError: Error, CustomStringConvertible {
        var description: String { "usage: ripper-bench (--bv BV… | --playurl file.json) [--cookies file] [--mb 16] [--mode overseas|mainland] [--quality 80] [--codec hevc|av1|avc]" }
    }

    static func main() async {
        do {
            try await run(parse(Array(CommandLine.arguments.dropFirst())))
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            guard let value = iterator.next() else { throw UsageError() }
            switch flag {
            case "--bv": options.bvid = value
            case "--cookies": options.cookies = value
            case "--playurl": options.playurl = value
            case "--mb": options.megabytes = Int(value) ?? 16
            case "--mode": options.mode = value == "mainland" ? .mainland : .overseas
            case "--quality": options.quality = Int(value) ?? 80
            case "--codec": options.codec = VideoCodec(rawValue: value) ?? .hevc
            default: throw UsageError()
            }
        }
        guard options.bvid != nil || options.playurl != nil else { throw UsageError() }
        return options
    }

    static func loadPlayURL(_ options: Options) async throws -> PlayURLInfo {
        if let path = options.playurl {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let envelope = try JSONDecoder().decode(BiliEnvelope<PlayURLInfo>.self, from: data)
            guard let info = envelope.data else { throw BiliError.api(code: envelope.code, message: envelope.message ?? "") }
            return info
        }
        guard let bvid = options.bvid else { throw UsageError() }
        // The cookie file holds one Cookie header line; its values are never printed.
        let header = options.cookies.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        let client = BiliClient(transport: URLSessionHTTPTransport(),
                                cookies: CookieJar(CookieJar.parse(header: header.trimmingCharacters(in: .whitespacesAndNewlines))))
        try await client.ensureRiskCookies()
        let view = try await client.view(bvid: bvid)
        guard let page = view.pages.first else { throw BiliError.invalidLink }
        print("\(view.title) (cid \(page.cid))")
        return try await client.playURL(bvid: view.bvid, cid: page.cid, quality: options.quality)
    }

    static func run(_ options: Options) async throws {
        let info = try await loadPlayURL(options)
        guard let dash = info.dash,
              let choice = TrackSelector.choose(dash, quality: options.quality, codecOrder: [options.codec, .hevc, .avc, .av1]) else {
            throw BiliError.notDash
        }
        let video = choice.video
        print("video \(video.id) \(video.codecs) \(video.width)x\(video.height) \(video.bandwidth / 1000) kbps on \(NodeCatalog.nodeKey(of: video.baseURL))")
        let transport = URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
        let target = Int64(options.megabytes) << 20

        let singleStart = Date()
        let singleRange = ByteRange(start: video.indexRange.end + 1, end: video.indexRange.end + target)!
        let response = try await transport.fetch(URL(string: video.baseURL)!, range: singleRange)
        var singleBytes: Int64 = 0
        if response.status == 206 {
            for try await chunk in response.body { singleBytes += Int64(chunk.count) }
        }
        let singleSeconds = Date().timeIntervalSince(singleStart)

        let session = RipperSession(sources: [.video: (video.baseURL, video.backupURLs)], mode: options.mode,
                                    transport: transport, auto: AutoConcurrency())
        let rippedStart = Date()
        let headers = try await session.loadHeaders(.video, through: video.indexRange.end)
        guard let segments = SidxParser.parse(headers.bytes, absoluteStart: 0) else { throw BiliError.decoding("no sidx") }
        session.setSegments(.video, segments)
        var rippedBytes: Int64 = 0
        for segment in segments where rippedBytes < target {
            for try await chunk in session.read(.video, segment.range) { rippedBytes += Int64(chunk.count) }
            session.updatePlayhead(seconds: segment.startTime, rate: 1)
        }
        let rippedSeconds = Date().timeIntervalSince(rippedStart)
        let stats = session.stats()
        session.close()

        func rate(_ bytes: Int64, _ seconds: Double) -> String {
            String(format: "%.2f MB/s", Double(bytes) / 1_048_576 / max(seconds, 0.001))
        }
        print("one connection: \(singleBytes) bytes in \(String(format: "%.2f", singleSeconds)) s = \(rate(singleBytes, singleSeconds)) (HTTP \(response.status))")
        print("ripper:         \(rippedBytes) bytes in \(String(format: "%.2f", rippedSeconds)) s = \(rate(rippedBytes, rippedSeconds))")
        print("connections \(stats.concurrency), requests \(stats.requests), failures \(stats.failures), duplicate \(String(format: "%.1f", stats.duplicateShare * 100))%")
        for node in stats.nodes {
            let state = stats.nodeStates.first { $0.node == node.node }
            print("  \(node.node): \(node.requests) req, \(node.failures) failed, first byte \(Int(node.firstByteMs)) ms, \(state.map { rate(Int64($0.bps), 1) } ?? "-") per connection, \(state?.state ?? "-")")
        }
    }
}
```

- [ ] **Step 4: Build and run it live**

Run: `swift build --package-path ios/Packages/BiliCore --product ripper-bench`
Expected: builds on Windows.

Run: `swift run --package-path ios/Packages/BiliCore ripper-bench --bv BV1GJ411x7h7 --mb 8`
Expected: either the two result lines plus per-node lines, or an HTTP 412 / decoding error from the API. If the API refuses (it refused non-browser requests from this PC in 2026-09), ask KaiC to save a playurl response from his browser (DevTools → Network → `playurl` → Copy response) into `scratchpad/playurl.json` and run with `--playurl` instead. The signed URLs in that file expire after a few hours; do not commit it. Report both numbers to KaiC; they are the first real evidence for or against the engine.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add URLSession range transport and ripper-bench"
```

---
### Task 21: LocalHTTP, request parsing, range handling and the playback router

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LocalHTTP/HTTPRequestParser.swift`, `Sources/LocalHTTP/HTTPResponseWriter.swift`, `Sources/LocalHTTP/RangeRequest.swift`, `Sources/LocalHTTP/PlaybackRouter.swift`
- Test: `Tests/LocalHTTPTests/LocalHTTPTests.swift`

**Interfaces:**
- Consumes: `ByteRange`, `Locked`.
- Produces: `HTTPRequestHead` (`method`, `target`, `path`, `headers` lowercased); `HTTPParseResult` (`incomplete`, `invalid`, `complete(HTTPRequestHead, headerLength:)`); `HTTPRequestParser.parse(_:)`; `HTTPResponseWriter.head(status:headers:) -> [UInt8]`; `RangeRequest` (`full`, `range(ByteRange)`, `unsatisfiable`) with `parse(_:totalSize:)`; `MediaResource(totalSize:prefix:read:)`; `PlaybackAssets(playlists:media:)`; `RouteResult` (`text(status:contentType:body:)`, `media(status:headers:body:)`, `failure(status:headers:)`); `PlaybackRouter` with `makeToken()`, `register(_:token:) -> String`, `unregister(_:)`, `route(_:) -> RouteResult`.

Paths are `/<token>/<name>`. `prefix` holds bytes served from memory (the patched init segment plus index); everything after it comes from `read`.

- [ ] **Step 1: Register the module**

In `Package.swift` add `"LocalHTTP"` to the product and:

```swift
        .target(name: "LocalHTTP", dependencies: ["BiliShared"]),
        .testTarget(name: "LocalHTTPTests", dependencies: ["LocalHTTP", "BiliShared"]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/LocalHTTPTests/LocalHTTPTests.swift`:

```swift
import XCTest
import BiliShared
@testable import LocalHTTP

final class LocalHTTPTests: XCTestCase {
    func testParserStates() {
        XCTAssertEqual(HTTPRequestParser.parse(Array("GET /a HTTP/1.1\r\nHost: x\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(Array("NONSENSE\r\n\r\n".utf8)), .invalid)
        let raw = Array("GET /tok/v.mp4?x=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-99\r\nX-Playback-Session-Id: 1\r\n\r\n".utf8)
        guard case .complete(let head, let length) = HTTPRequestParser.parse(raw) else { return XCTFail("expected complete") }
        XCTAssertEqual(length, raw.count)
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.path, "/tok/v.mp4")
        XCTAssertEqual(head.target, "/tok/v.mp4?x=1")
        XCTAssertEqual(head.headers["range"], "bytes=0-99")
        XCTAssertEqual(head.headers["x-playback-session-id"], "1")
        XCTAssertEqual(HTTPRequestParser.parse([UInt8](repeating: 65, count: 20_000)), .invalid)
    }

    /// Review focus 4: whatever range AVPlayer sends gets the right bytes.
    func testRangeVariants() {
        XCTAssertEqual(RangeRequest.parse(nil, totalSize: 1000), .full)
        XCTAssertEqual(RangeRequest.parse("bytes=0-99", totalSize: 1000), .range(ByteRange(start: 0, end: 99)!))
        XCTAssertEqual(RangeRequest.parse("bytes=900-", totalSize: 1000), .range(ByteRange(start: 900, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=-100", totalSize: 1000), .range(ByteRange(start: 900, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=0-5000", totalSize: 1000), .range(ByteRange(start: 0, end: 999)!))
        XCTAssertEqual(RangeRequest.parse("bytes=1000-", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=0-1,5-6", totalSize: 1000), .unsatisfiable)
        XCTAssertEqual(RangeRequest.parse("bytes=50-10", totalSize: 1000), .unsatisfiable)
    }

    func testResponseHead() {
        let text = String(decoding: HTTPResponseWriter.head(status: 206, headers: [("Content-Length", "10")]), as: UTF8.self)
        XCTAssertEqual(text, "HTTP/1.1 206 Partial Content\r\nContent-Length: 10\r\n\r\n")
    }

    // MARK: router

    let content: [UInt8] = (0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 7) }

    func makeRouter(reads: Locked<[ByteRange]>) -> (PlaybackRouter, String) {
        let content = self.content
        let media = MediaResource(totalSize: 1000, prefix: Array(content[0..<100])) { range in
            reads.withLock { $0.append(range) }
            return AsyncThrowingStream { continuation in
                continuation.yield(Array(content[Int(range.start)...Int(range.end)]))
                continuation.finish()
            }
        }
        let router = PlaybackRouter()
        let token = router.register(PlaybackAssets(playlists: ["master.m3u8": "#EXTM3U\n"], media: ["v.mp4": media]))
        return (router, token)
    }

    func head(_ path: String, range: String? = nil, method: String = "GET") -> HTTPRequestHead {
        HTTPRequestHead(method: method, target: path, path: path, headers: range.map { ["range": $0] } ?? [:])
    }

    func body(_ result: RouteResult) async throws -> (Int, [(String, String)], [UInt8]) {
        switch result {
        case .text(let status, _, let body): return (status, [], body)
        case .failure(let status, let headers): return (status, headers, [])
        case .media(let status, let headers, let stream):
            var bytes: [UInt8] = []
            for try await chunk in stream { bytes += chunk }
            return (status, headers, bytes)
        }
    }

    func testPlaylistAndUnknownPaths() async throws {
        let (router, token) = makeRouter(reads: Locked([]))
        let (status, _, bytes) = try await body(router.route(head("/\(token)/master.m3u8")))
        XCTAssertEqual(status, 200)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "#EXTM3U\n")
        XCTAssertEqual(try await body(router.route(head("/wrongtoken/master.m3u8"))).0, 404)
        XCTAssertEqual(try await body(router.route(head("/\(token)/nope.mp4"))).0, 404)
        XCTAssertEqual(try await body(router.route(head("/\(token)/master.m3u8", method: "POST"))).0, 405)
        router.unregister(token)
        XCTAssertEqual(try await body(router.route(head("/\(token)/master.m3u8"))).0, 404)
    }

    func testRangesInsideAcrossAndAfterThePrefix() async throws {
        let reads = Locked<[ByteRange]>([])
        let (router, token) = makeRouter(reads: reads)

        let (status, headers, inside) = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=0-49")))
        XCTAssertEqual(status, 206)
        XCTAssertEqual(inside, Array(content[0...49]))
        XCTAssertTrue(headers.contains { $0 == ("Content-Range", "bytes 0-49/1000") })
        XCTAssertTrue(headers.contains { $0 == ("Content-Length", "50") })
        XCTAssertTrue(reads.current.isEmpty)

        XCTAssertEqual(try await body(router.route(head("/\(token)/v.mp4", range: "bytes=50-199"))).2, Array(content[50...199]))
        XCTAssertEqual(reads.current, [ByteRange(start: 100, end: 199)!])

        XCTAssertEqual(try await body(router.route(head("/\(token)/v.mp4", range: "bytes=500-"))).2, Array(content[500...999]))
        XCTAssertEqual(try await body(router.route(head("/\(token)/v.mp4"))).0, 200)
        let (refused, refusedHeaders, _) = try await body(router.route(head("/\(token)/v.mp4", range: "bytes=2000-")))
        XCTAssertEqual(refused, 416)
        XCTAssertTrue(refusedHeaders.contains { $0 == ("Content-Range", "bytes */1000") })
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --package-path ios/Packages/BiliCore --filter LocalHTTPTests`
Expected: compile errors.

- [ ] **Step 4: Implement parsing, ranges and the response head**

`Sources/LocalHTTP/HTTPRequestParser.swift`:

```swift
import Foundation

public struct HTTPRequestHead: Equatable, Sendable {
    public let method: String
    public let target: String
    public let path: String
    /// Lowercased names.
    public let headers: [String: String]

    public init(method: String, target: String, path: String, headers: [String: String]) {
        self.method = method
        self.target = target
        self.path = path
        self.headers = headers
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case incomplete
    case invalid
    case complete(HTTPRequestHead, headerLength: Int)
}

public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024

    public static func parse(_ bytes: [UInt8]) -> HTTPParseResult {
        guard let end = headerEnd(bytes) else { return bytes.count > maxHeaderBytes ? .invalid : .incomplete }
        let lines = String(decoding: bytes[0..<end], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        let target = String(requestLine[1])
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return .complete(HTTPRequestHead(method: requestLine[0].uppercased(), target: target, path: path, headers: headers),
                         headerLength: end + 4)
    }

    private static func headerEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4) where bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
            return index
        }
        return nil
    }
}
```

`Sources/LocalHTTP/HTTPResponseWriter.swift`:

```swift
public enum HTTPResponseWriter {
    public static func head(status: Int, headers: [(String, String)]) -> [UInt8] {
        var text = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (name, value) in headers { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        return Array(text.utf8)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }
}
```

`Sources/LocalHTTP/RangeRequest.swift`:

```swift
import Foundation
import BiliShared

public enum RangeRequest: Equatable, Sendable {
    case full
    case range(ByteRange)
    case unsatisfiable

    /// Single ranges only: "a-b", "a-" and the suffix form "-n". An end past the file is clamped.
    public static func parse(_ header: String?, totalSize: Int64) -> RangeRequest {
        guard let header = header?.trimmingCharacters(in: .whitespaces).lowercased(), !header.isEmpty else { return .full }
        guard header.hasPrefix("bytes="), totalSize > 0 else { return .unsatisfiable }
        let spec = header.dropFirst(6)
        guard !spec.contains(",") else { return .unsatisfiable }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return .unsatisfiable }
        let start: Int64
        let end: Int64
        if parts[0].isEmpty {
            guard let suffix = Int64(parts[1]), suffix > 0 else { return .unsatisfiable }
            start = max(0, totalSize - suffix)
            end = totalSize - 1
        } else {
            guard let first = Int64(parts[0]) else { return .unsatisfiable }
            start = first
            if parts[1].isEmpty {
                end = totalSize - 1
            } else {
                guard let last = Int64(parts[1]) else { return .unsatisfiable }
                end = min(last, totalSize - 1)
            }
        }
        guard start < totalSize, let range = ByteRange(start: start, end: end) else { return .unsatisfiable }
        return .range(range)
    }
}
```

- [ ] **Step 5: Implement the router**

`Sources/LocalHTTP/PlaybackRouter.swift`:

```swift
import Foundation
import BiliShared

public struct MediaResource: Sendable {
    public let totalSize: Int64
    /// Served from memory: the (patched) init segment and index.
    public let prefix: [UInt8]
    public let read: @Sendable (ByteRange) -> AsyncThrowingStream<[UInt8], Error>

    public init(totalSize: Int64, prefix: [UInt8], read: @escaping @Sendable (ByteRange) -> AsyncThrowingStream<[UInt8], Error>) {
        self.totalSize = totalSize
        self.prefix = prefix
        self.read = read
    }
}

public struct PlaybackAssets: Sendable {
    public var playlists: [String: String]
    public var media: [String: MediaResource]

    public init(playlists: [String: String], media: [String: MediaResource]) {
        self.playlists = playlists
        self.media = media
    }
}

public enum RouteResult {
    case text(status: Int, contentType: String, body: [UInt8])
    case media(status: Int, headers: [(String, String)], body: AsyncThrowingStream<[UInt8], Error>)
    case failure(status: Int, headers: [(String, String)])
}

public final class PlaybackRouter: @unchecked Sendable {
    private let entries = Locked<[String: PlaybackAssets]>([:])

    public init() {}

    /// 128 random bits as hex: the server listens on localhost only, and the token keeps other
    /// processes from guessing a playback's paths.
    public static func makeToken() -> String {
        (0..<4).map { _ in
            let hex = String(UInt32.random(in: .min ... .max), radix: 16)
            return String(repeating: "0", count: 8 - hex.count) + hex
        }.joined()
    }

    @discardableResult
    public func register(_ assets: PlaybackAssets, token: String = PlaybackRouter.makeToken()) -> String {
        entries.withLock { $0[token] = assets }
        return token
    }

    public func unregister(_ token: String) {
        entries.withLock { $0[token] = nil }
    }

    public func route(_ head: HTTPRequestHead) -> RouteResult {
        guard head.method == "GET" || head.method == "HEAD" else { return .failure(status: 405, headers: []) }
        let parts = head.path.split(separator: "/").map(String.init)
        guard parts.count == 2, let assets = entries.current[parts[0]] else { return .failure(status: 404, headers: []) }
        if let playlist = assets.playlists[parts[1]] {
            return .text(status: 200, contentType: "application/vnd.apple.mpegurl", body: Array(playlist.utf8))
        }
        guard let media = assets.media[parts[1]] else { return .failure(status: 404, headers: []) }
        let status: Int
        let range: ByteRange
        switch RangeRequest.parse(head.headers["range"], totalSize: media.totalSize) {
        case .unsatisfiable:
            return .failure(status: 416, headers: [("Content-Range", "bytes */\(media.totalSize)")])
        case .full:
            guard let whole = ByteRange(start: 0, end: media.totalSize - 1) else { return .failure(status: 416, headers: []) }
            status = 200
            range = whole
        case .range(let requested):
            status = 206
            range = requested
        }
        var headers = [("Content-Type", "video/mp4"), ("Accept-Ranges", "bytes"), ("Content-Length", "\(range.length)")]
        if status == 206 { headers.append(("Content-Range", "bytes \(range.start)-\(range.end)/\(media.totalSize)")) }
        return .media(status: status, headers: headers, body: Self.body(media, range))
    }

    static func body(_ media: MediaResource, _ range: ByteRange) -> AsyncThrowingStream<[UInt8], Error> {
        let prefixEnd = Int64(media.prefix.count) - 1
        if range.end <= prefixEnd {
            let bytes = Array(media.prefix[Int(range.start)...Int(range.end)])
            return AsyncThrowingStream { continuation in
                continuation.yield(bytes)
                continuation.finish()
            }
        }
        if range.start > prefixEnd { return media.read(range) }
        let head = Array(media.prefix[Int(range.start)...Int(prefixEnd)])
        guard let rest = ByteRange(start: prefixEnd + 1, end: range.end) else { return media.read(range) }
        let tail = media.read(rest)
        return AsyncThrowingStream { continuation in
            continuation.yield(head)
            let task = Task {
                do {
                    for try await chunk in tail { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `swift test --package-path ios/Packages/BiliCore --filter LocalHTTPTests`
Expected: 5 tests pass. Run the full package suite and confirm everything passes on Windows; push and confirm "Core tests" is green on GitHub.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/BiliCore
git commit -m "Add LocalHTTP request parsing and playback router"
git push
```

---

### Task 22: iOS project scaffold, CI compile check and TestFlight pipeline

This task needs a Mac only through GitHub Actions. **Load the `ios-testflight` skill first** and follow its "first-time setup" for a new XcodeGen app. Values for every placeholder in its templates:

| Placeholder | Value |
|---|---|
| `__APP__` | `BiliNative` |
| `__BUNDLE_ID__` | `com.kaichuan.bilinative` |
| `REPO` | `KaiC5504/BiliNative` |
| `__ASC_APP_ID__` | from App Store Connect after KaiC creates the app record (OWNER step below) |
| Project path | `ios/BiliNative.xcodeproj` (generated, gitignored) |

**Files:**
- Create: `ios/project.yml`, `ios/Sources/App/BiliNativeApp.swift`, `ios/Sources/App/RootView.swift`, `ios/Sources/App/AppInfo.swift`, `ios/Resources/Localizable.xcstrings`, `ios/Resources/Assets.xcassets/...` (via `scripts/icons.py --apply`), `ios/Tests/AppTests/SmokeTests.swift`
- Create: `.github/workflows/ios-compile.yml`, `.github/workflows/testflight.yml`, `scripts/testflight.py`, `scripts/testflight-requirements.txt` (the last three copied from the skill's templates/scripts and filled in)
- Modify: `CLAUDE.md` (create it) with the skill's `templates/CLAUDE-section.md`

**Interfaces:**
- Produces: app target `BiliNative`, unit-test target `BiliNativeTests` hosted in the app, scheme `BiliNative` that builds both and tests `BiliNativeTests`; compile condition `DEV_TOOLS` in all configurations; `AppInfo.displayName`, `AppInfo.version`.

- [ ] **Step 1: Install the icon**

Run: `uv run scripts/icons.py --apply N` where N is the concept number in `design/CHOICES.md` (1 if KaiC has not chosen yet).
Expected: `ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` and the two `Contents.json` files exist.

- [ ] **Step 2: Write the XcodeGen spec**

`ios/project.yml` (based on the skill's template; display name from `design/CHOICES.md`, default `BiliNative`):

```yaml
name: BiliNative

options:
  bundleIdPrefix: com.kaichuan
  deploymentTarget:
    iOS: "26.0"
  developmentLanguage: zh-Hans
  createIntermediateGroups: true
  groupSortPosition: top

settings:
  base:
    # Swift 5 mode on purpose (see the ios-testflight template): strict concurrency cannot be
    # iterated on without a Mac.
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    CODE_SIGN_STYLE: Automatic
    # Internal builds stream logs to the PC; a public release build drops DEV_TOOLS.
    SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) DEV_TOOLS"

packages:
  BiliCore:
    path: Packages/BiliCore

targets:
  BiliNative:
    type: application
    platform: iOS
    sources:
      - path: Sources/App
      - path: Resources
    dependencies:
      - package: BiliCore
        product: BiliCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kaichuan.bilinative
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: Generated/BiliNative-Info.plist
      properties:
        CFBundleDisplayName: BiliNative
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleIconName: AppIcon
        CFBundleDevelopmentRegion: zh-Hans
        ITSAppUsesNonExemptEncryption: false
        UILaunchScreen: {}
        UIBackgroundModes:
          - audio
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
        NSLocalNetworkUsageDescription: 用于把调试日志发送到你电脑上的日志服务器。
        NSBonjourServices:
          - _bilinative-log._tcp
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight

  BiliNativeTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/AppTests
    dependencies:
      - target: BiliNative
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.kaichuan.bilinative.tests

schemes:
  BiliNative:
    build:
      targets:
        BiliNative: all
        BiliNativeTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - BiliNativeTests
    archive:
      config: Release
```

The test target deliberately does not link `BiliCore` again (that would put a second copy of every engine type into the test bundle). Tests import only `BiliNative` with `@testable import`; anything they need from the engine is reached through the app module (`DebugSupport`, Task 28). If the test build fails with "missing required module" for a BiliCore module, add `SWIFT_INCLUDE_PATHS: $(BUILT_PRODUCTS_DIR)` to the test target's settings rather than linking the package a second time.

- [ ] **Step 3: Write the minimal app**

`ios/Sources/App/AppInfo.swift`:

```swift
import Foundation

enum AppInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "BiliNative"
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
```

`ios/Sources/App/BiliNativeApp.swift`:

```swift
import SwiftUI

@main
struct BiliNativeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`ios/Sources/App/RootView.swift`:

```swift
import SwiftUI
import Ripper

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("版本 \(AppInfo.version)")
                Text("引擎节点：\(NodeCatalog.overseas.count) 个海外节点")
            }
            .navigationTitle(AppInfo.displayName)
        }
    }
}
```

`ios/Resources/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {},
  "version" : "1.0"
}
```

`ios/Tests/AppTests/SmokeTests.swift`:

```swift
import XCTest
@testable import BiliNative

final class SmokeTests: XCTestCase {
    func testAppInfoReadsTheBundle() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }
}
```

- [ ] **Step 4: Add the compile workflow**

`.github/workflows/ios-compile.yml` (the skill's `templates/ios-compile.yml`, filled in, with the core tests and the unit tests switched on):

```yaml
name: iOS compile check

on:
  push:
    paths:
      - "ios/**"
      - ".github/workflows/ios-compile.yml"
  workflow_dispatch:

concurrency:
  group: ios-compile-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Toolchain
        run: |
          NEWEST=$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1)
          if [ -n "$NEWEST" ]; then sudo xcode-select -s "$NEWEST"; fi
          xcodebuild -version

      - name: Core package tests
        run: swift test --package-path ios/Packages/BiliCore

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate project
        run: cd ios && xcodegen generate

      - name: Boot a simulator
        id: sim
        run: |
          UDID=$(xcrun simctl list devices available -j | python3 -c "
          import json, sys
          best = None
          for runtime, items in json.load(sys.stdin)['devices'].items():
              if 'iOS' not in runtime:
                  continue
              for device in items:
                  if 'iPhone' in device['name'] and device['isAvailable']:
                      best = device['udid']
          print(best)
          ")
          echo "udid=$UDID" >> "$GITHUB_OUTPUT"
          xcrun simctl boot "$UDID"
          xcrun simctl bootstatus "$UDID" -b

      - name: Build and test on the simulator
        run: |
          set -o pipefail
          xcodebuild \
            -project ios/BiliNative.xcodeproj \
            -scheme BiliNative \
            -destination "id=${{ steps.sim.outputs.udid }}" \
            -configuration Debug \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=YES \
            test

      - name: Install, launch and screenshot
        run: |
          UDID="${{ steps.sim.outputs.udid }}"
          APP=com.kaichuan.bilinative
          xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/BiliNative.app
          mkdir -p shots
          xcrun simctl launch "$UDID" $APP
          sleep 15
          xcrun simctl io "$UDID" screenshot shots/01-first-launch.png
          shoot() {
            name=$1; wait=$2; shift 2
            xcrun simctl terminate "$UDID" $APP || true
            xcrun simctl launch "$UDID" $APP -DemoData YES "$@"
            sleep "$wait"
            xcrun simctl io "$UDID" screenshot "shots/$name.png"
          }

      - name: Collect crash reports
        if: always()
        run: |
          mkdir -p shots/crashes
          find ~/Library/Logs/DiagnosticReports -name "BiliNative*" -exec cp {} shots/crashes/ \; 2>/dev/null || true
          if [ -n "$(ls -A shots/crashes 2>/dev/null)" ]; then
            echo "CRASHES FOUND:"; head -60 shots/crashes/* || true
          fi

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: simulator-screenshots
          path: shots/
```

Later tasks add `shoot` lines and the integration test media step.

- [ ] **Step 5: Add the TestFlight workflow, script and CLAUDE.md**

Copy `templates/testflight.yml` to `.github/workflows/testflight.yml`, `scripts/testflight.py` and `templates/testflight-requirements.txt` to `scripts/`, and `templates/CLAUDE-section.md` into a new `CLAUDE.md`, replacing the placeholders from the table above. Pin every action to a commit SHA as the template says (look up the current release SHAs with `gh api repos/actions/checkout/releases/latest` etc.). Keep the XcodeGen variant (not the "Make the project ours" fork variant).

- [ ] **Step 6: Push and check the compile workflow**

```bash
git add ios .github scripts CLAUDE.md
git commit -m "Add iOS app scaffold, compile check and TestFlight pipeline"
git push
```

Run: `gh run watch` on the "iOS compile check" run.
Expected: green, with the `simulator-screenshots` artifact showing the version line and "引擎节点：4 个海外节点". Download it with `gh run download --name simulator-screenshots` and look at `01-first-launch.png`. If XcodeGen or the build fails, fix it before going on.

- [ ] **Step 7: OWNER steps (KaiC, with the skill's `reference/manual-steps.md` open)**

Walk KaiC through, one at a time, waiting for each to be done:
1. Register the bundle id `com.kaichuan.bilinative` (or let the first `create_signing` run do it, per the skill).
2. Create the App Store Connect app record "BiliNative" (name can be changed later), primary language Simplified Chinese, and send the Apple ID number for `ASC_APP_ID`.
3. Create the `testflight` GitHub environment on `KaiC5504/BiliNative` with the secrets the skill lists, restricted to `main`.
4. Add himself as an internal tester.

Then fill `ASC_APP_ID`, commit, and run the skill's dry run: `python scripts/testflight.py start` with upload off and `create_signing` on.
Expected: the signed build and IPA check pass. The real upload happens in Task 29.

---

### Task 23: Keychain, settings, account state and the login page

**Files:**
- Create: `ios/Sources/App/Account/KeychainStore.swift`, `ios/Sources/App/Account/LoginView.swift`, `ios/Sources/App/AppSettings.swift`, `ios/Sources/App/AppEnvironment.swift`
- Modify: `ios/Sources/App/BiliNativeApp.swift`, `ios/Sources/App/RootView.swift`
- Test: `ios/Tests/AppTests/KeychainStoreTests.swift`, `ios/Tests/AppTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `CookieJar`, `BiliClient`, `URLSessionHTTPTransport`, `BiliError` (BiliAPI); `NodeMode` (Ripper); `VideoCodec` (BiliAPI); `Logger` (DevLog).
- Produces:
  - `KeychainStore.loadCookies() -> [String: String]`, `saveCookies(_:) -> Bool`, `deleteCookies()`.
  - `@MainActor @Observable AppSettings(defaults:)` with `nodeChoice` (`AppSettings.NodeChoice`: `overseas`, `mainland`, `label`, `mode`), `preferredQuality`, `preferredCodec`, `btrEnabled`, `showOverlay`, `logServerEnabled`, `logServerManual`, `logServerService`.
  - `@MainActor @Observable AppEnvironment` with `settings`, `cookies`, `client`, `account` (`AppEnvironment.Account`: `unknown`, `loggedOut`, `loggedIn(name:vip:)`, `expired`), `refreshAccount()`, `didLogin(_:)`, `logout()`. (Task 25 replaces this file with the full version.)
  - `LoginView` (sheet; reads `AppEnvironment` from the SwiftUI environment).

- [ ] **Step 1: Write the failing simulator tests**

`ios/Tests/AppTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import BiliNative

final class KeychainStoreTests: XCTestCase {
    override func tearDown() {
        KeychainStore.deleteCookies()
    }

    func testRoundTripAndDelete() {
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "abc", "bili_jct": "def"]))
        XCTAssertEqual(KeychainStore.loadCookies(), ["SESSDATA": "abc", "bili_jct": "def"])
        XCTAssertTrue(KeychainStore.saveCookies(["SESSDATA": "new"]))
        XCTAssertEqual(KeychainStore.loadCookies(), ["SESSDATA": "new"])
        KeychainStore.deleteCookies()
        XCTAssertEqual(KeychainStore.loadCookies(), [:])
    }
}
```

`ios/Tests/AppTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import BiliNative

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsAndPersistence() {
        let defaults = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.nodeChoice, .overseas)
        XCTAssertTrue(settings.btrEnabled)
        XCTAssertEqual(settings.preferredCodec, .hevc)
        settings.nodeChoice = .mainland
        settings.btrEnabled = false
        settings.logServerManual = "192.168.1.5:47321"
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.nodeChoice, .mainland)
        XCTAssertFalse(reloaded.btrEnabled)
        XCTAssertEqual(reloaded.logServerManual, "192.168.1.5:47321")
    }
}
```

App tests run only in CI (the compile workflow's `test` step); there is no local Xcode to watch them fail first. Write them together with the implementation below and confirm they pass in CI.

- [ ] **Step 2: Implement the Keychain store**

`ios/Sources/App/Account/KeychainStore.swift`:

```swift
import Foundation
import Security

/// The bilibili.com cookies, as one JSON blob in a generic-password item.
enum KeychainStore {
    private static let service = "com.kaichuan.bilinative.cookies"
    private static let account = "bilibili"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func loadCookies() -> [String: String] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let cookies = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return cookies
    }

    @discardableResult
    static func saveCookies(_ cookies: [String: String]) -> Bool {
        if cookies.isEmpty {
            deleteCookies()
            return true
        }
        guard let data = try? JSONEncoder().encode(cookies) else { return false }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery.merging(attributes) { $1 }
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func deleteCookies() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
```

- [ ] **Step 3: Implement the settings**

`ios/Sources/App/AppSettings.swift`:

```swift
import Foundation
import Observation
import BiliAPI
import Ripper

@MainActor
@Observable
final class AppSettings {
    enum NodeChoice: String, CaseIterable, Identifiable {
        case overseas, mainland

        var id: String { rawValue }
        var label: String { self == .overseas ? "海外节点" : "大陆节点" }
        var mode: NodeMode { self == .overseas ? .overseas : .mainland }
    }

    private enum Keys {
        static let node = "settings.node"
        static let quality = "settings.quality"
        static let codec = "settings.codec"
        static let btr = "settings.btr"
        static let overlay = "settings.overlay"
        static let logEnabled = "settings.log.enabled"
        static let logManual = "settings.log.manual"
        static let logService = "settings.log.service"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var nodeChoice: NodeChoice { didSet { defaults.set(nodeChoice.rawValue, forKey: Keys.node) } }
    /// Bilibili quality id; 120 is 4K, 80 is 1080P.
    var preferredQuality: Int { didSet { defaults.set(preferredQuality, forKey: Keys.quality) } }
    var preferredCodec: VideoCodec { didSet { defaults.set(preferredCodec.rawValue, forKey: Keys.codec) } }
    var btrEnabled: Bool { didSet { defaults.set(btrEnabled, forKey: Keys.btr) } }
    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Keys.overlay) } }
    var logServerEnabled: Bool { didSet { defaults.set(logServerEnabled, forKey: Keys.logEnabled) } }
    /// "192.168.1.5:47321"; used when no Bonjour service is chosen.
    var logServerManual: String { didSet { defaults.set(logServerManual, forKey: Keys.logManual) } }
    /// Name of the chosen Bonjour service, or "" for the manual address.
    var logServerService: String { didSet { defaults.set(logServerService, forKey: Keys.logService) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        nodeChoice = NodeChoice(rawValue: defaults.string(forKey: Keys.node) ?? "") ?? .overseas
        preferredQuality = defaults.object(forKey: Keys.quality) as? Int ?? 120
        preferredCodec = VideoCodec(rawValue: defaults.string(forKey: Keys.codec) ?? "") ?? .hevc
        btrEnabled = defaults.object(forKey: Keys.btr) as? Bool ?? true
        showOverlay = defaults.object(forKey: Keys.overlay) as? Bool ?? true
        logServerEnabled = defaults.object(forKey: Keys.logEnabled) as? Bool ?? false
        logServerManual = defaults.string(forKey: Keys.logManual) ?? ""
        logServerService = defaults.string(forKey: Keys.logService) ?? ""
    }
}
```

- [ ] **Step 4: Implement the environment (account part)**

`ios/Sources/App/AppEnvironment.swift`:

```swift
import Foundation
import Observation
import WebKit
import BiliAPI
import DevLog

@MainActor
@Observable
final class AppEnvironment {
    enum Account: Equatable {
        case unknown
        case loggedOut
        case loggedIn(name: String, vip: Bool)
        /// Cookies exist but Bilibili no longer accepts them.
        case expired
    }

    let settings = AppSettings()
    @ObservationIgnored let cookies: CookieJar
    @ObservationIgnored let client: BiliClient
    private(set) var account: Account = .unknown

    init() {
        cookies = CookieJar(KeychainStore.loadCookies())
        cookies.onChange = { KeychainStore.saveCookies($0) }
        client = BiliClient(transport: URLSessionHTTPTransport(), cookies: cookies)
    }

    func refreshAccount() async {
        do {
            try await client.ensureRiskCookies()
            let nav = try await client.nav()
            if nav.isLogin {
                account = .loggedIn(name: nav.uname ?? "", vip: nav.isVip)
                Logger.shared.info(.app, "account", ["user": .init(nav.mid.map(Redactor.mid) ?? "?"), "vip": .init(nav.isVip)])
            } else {
                account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired
            }
        } catch {
            Logger.shared.warn(.app, "nav failed", ["error": .init(String(describing: error))])
            if account == .unknown { account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired }
        }
    }

    func didLogin(_ webCookies: [String: String]) async {
        var merged = cookies.all
        merged.merge(webCookies) { _, new in new }
        cookies.replaceAll(merged)
        await refreshAccount()
    }

    func logout() async {
        cookies.removeAll()
        KeychainStore.deleteCookies()
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        account = .loggedOut
    }
}
```

- [ ] **Step 5: Implement the login page**

`ios/Sources/App/Account/LoginView.swift`:

```swift
import SwiftUI
import WebKit
import DevLog

/// Bilibili's own login page (password, SMS or QR; it handles its own captcha). The app never sees
/// the password: it only copies the bilibili.com cookies once `SESSDATA` appears.
struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoginWebView { cookies in
                Task {
                    await env.didLogin(cookies)
                    dismiss()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("登录哔哩哔哩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct LoginWebView: UIViewRepresentable {
    let onLogin: ([String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLogin: onLogin)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.store = configuration.websiteDataStore.httpCookieStore
        webView.load(URLRequest(url: URL(string: "https://passport.bilibili.com/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onLogin: ([String: String]) -> Void
        weak var store: WKHTTPCookieStore?
        private var finished = false

        init(onLogin: @escaping ([String: String]) -> Void) {
            self.onLogin = onLogin
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            check(cookieStore)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Logger.shared.info(.ui, "login page", ["url": .init(webView.url?.absoluteString ?? "")])
            if let store { check(store) }
        }

        private func check(_ cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished else { return }
                let bilibili = cookies.filter { $0.domain.hasSuffix("bilibili.com") }
                guard bilibili.contains(where: { $0.name == "SESSDATA" && !$0.value.isEmpty }) else { return }
                self.finished = true
                self.onLogin(Dictionary(bilibili.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first }))
            }
        }
    }
}
```

- [ ] **Step 6: Show the account on the root screen**

Replace `ios/Sources/App/BiliNativeApp.swift`:

```swift
import SwiftUI

@main
struct BiliNativeApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
        }
    }
}
```

Replace `ios/Sources/App/RootView.swift`:

```swift
import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            List {
                Section("账号") { AccountRow(showLogin: $showLogin) }
                Section { Text("版本 \(AppInfo.version)") }
            }
            .navigationTitle(AppInfo.displayName)
            .sheet(isPresented: $showLogin) { LoginView() }
            .task { await env.refreshAccount() }
        }
    }
}

struct AccountRow: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var showLogin: Bool

    var body: some View {
        switch env.account {
        case .unknown:
            ProgressView()
        case .loggedOut:
            Button("登录哔哩哔哩") { showLogin = true }
        case .expired:
            Button("登录已过期，重新登录") { showLogin = true }
                .foregroundStyle(.orange)
        case .loggedIn(let name, let vip):
            HStack {
                Text(name)
                if vip {
                    Text("大会员")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.pink.opacity(0.15), in: Capsule())
                        .foregroundStyle(.pink)
                }
                Spacer()
                Button("退出") { Task { await env.logout() } }
                    .font(.footnote)
            }
        }
    }
}
```

- [ ] **Step 7: Push and check CI**

```bash
git add ios
git commit -m "Add Keychain cookie store, settings, account state and login page"
git push
```

Run: `gh run watch` for "iOS compile check".
Expected: green; `KeychainStoreTests` and `AppSettingsTests` pass; the screenshot shows "登录哔哩哔哩" (the simulator has no account; the nav call may fail offline, which still ends in the logged-out row).

---
### Task 24: The in-app server, direct-mode playlists and playback assembly

**Files:**
- Create: `ios/Sources/App/Playback/LocalServer.swift`, `ios/Sources/App/Playback/DirectPlaylistLoader.swift`, `ios/Sources/App/Playback/PlaybackBuilder.swift`
- Test: `ios/Tests/AppTests/LocalServerTests.swift`

**Interfaces:**
- Consumes: `PlaybackRouter`, `HTTPRequestParser`, `HTTPResponseWriter`, `PlaybackAssets`, `MediaResource` (LocalHTTP); `Locked` (BiliShared); `TrackChoice`, `DashStream` (BiliAPI); `SidxParser`, `InitSegmentFixer`, `CodecMapper`, `PlaylistBuilder`, `HLSTrack`, `HLSVariant` (DashHLS); `RipperSession`, `TrackKind`, `RangeTransport` (Ripper); `Logger`.
- Produces:
  - `LocalServer(router:)` with `start() async throws`, `stop()`, `isRunning`, `port`, `url(token:name:) -> URL?`, `onStop: (() -> Void)?`.
  - `DirectPlaylistLoader` (`scheme`, `queue`, `register(token:playlists:) -> URL`, `unregister(_:)`), an `AVAssetResourceLoaderDelegate`.
  - `PreparedTrack` (`stream`, `headers`, `totalSize`, `segments`, `initRange`), `PreparedPlayback` (`video`, `audio`, `videoCodec`, `rewroteHEV1`), `PlaybackError` (`noSidx`, `codecUnplayable(String)`, `noTrack`, `serverDown`).
  - `PlaybackBuilder.prepare(choice:fetchHeaders:) async throws -> PreparedPlayback`, `PlaybackBuilder.ripperAssets(_:session:) -> PlaybackAssets`, `PlaybackBuilder.directPlaylists(_:token:) -> [String: String]`, `PlaybackBuilder.directHeaders(_:transport:) async throws -> (bytes: [UInt8], total: Int64)`.

- [ ] **Step 1: Write the server test**

`ios/Tests/AppTests/LocalServerTests.swift`:

```swift
import XCTest
@testable import BiliNative

final class LocalServerTests: XCTestCase {
    func testServesPlaylistsAndRanges() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let token = DebugSupport.registerStaticAssets(on: server, size: 10_000)

        let playlistURL = try XCTUnwrap(server.url(token: token, name: "master.m3u8"))
        let (playlist, playlistResponse) = try await URLSession.shared.data(from: playlistURL)
        XCTAssertEqual((playlistResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: playlist, as: UTF8.self), "#EXTM3U\n")

        var request = URLRequest(url: try XCTUnwrap(server.url(token: token, name: "v.mp4")))
        request.setValue("bytes=50-149", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 50-149/10000")
        XCTAssertEqual(Array(bytes), DebugSupport.staticContent(size: 10_000, range: 50...149))

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port!)/nope/master.m3u8")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }
}
```

`DebugSupport` is created in this task too (it grows in Task 28). Create `ios/Sources/App/DebugSupport/DebugSupport.swift`:

```swift
#if DEBUG
import Foundation
import BiliShared
import LocalHTTP

/// Helpers for the simulator tests, compiled into Debug builds only. The test target links no
/// engine modules of its own, so engine values are built here inside the app module.
enum DebugSupport {
    static func makeRouter() -> PlaybackRouter { PlaybackRouter() }

    static func staticContent(size: Int, range: ClosedRange<Int>) -> [UInt8] {
        range.map { UInt8(truncatingIfNeeded: $0 &* 13) }
    }

    /// master.m3u8 plus a media file "v.mp4" whose first 100 bytes come from memory.
    static func registerStaticAssets(on server: LocalServer, size: Int) -> String {
        let all = staticContent(size: size, range: 0...(size - 1))
        let media = MediaResource(totalSize: Int64(size), prefix: Array(all[0..<100])) { range in
            AsyncThrowingStream { continuation in
                continuation.yield(Array(all[Int(range.start)...Int(range.end)]))
                continuation.finish()
            }
        }
        return server.router.register(PlaybackAssets(playlists: ["master.m3u8": "#EXTM3U\n"], media: ["v.mp4": media]))
    }
}
#endif
```

- [ ] **Step 2: Implement the local server**

`ios/Sources/App/Playback/LocalServer.swift`:

```swift
import Foundation
import Network
import BiliShared
import LocalHTTP
import DevLog

/// HTTP/1.1 on 127.0.0.1, one request per connection. AVPlayer fetches HLS playlists and media
/// ranges from here; media bodies stream from the BTR engine as they arrive.
final class LocalServer: @unchecked Sendable {
    enum State: Equatable {
        case stopped
        case starting
        case ready(UInt16)
        case failed(String)
    }

    let router: PlaybackRouter
    private let queue = DispatchQueue(label: "bilinative.local-server")
    private let stateBox = Locked<State>(.stopped)
    private let listenerBox = Locked<NWListener?>(nil)
    private let connections = Locked<[ObjectIdentifier: NWConnection]>([:])
    /// Called when a running server stops unexpectedly (or is stopped), so playback can fall back.
    var onStop: (() -> Void)?

    init(router: PlaybackRouter) {
        self.router = router
    }

    var state: State { stateBox.current }

    var isRunning: Bool {
        if case .ready = state { return true }
        return false
    }

    var port: UInt16? {
        if case .ready(let port) = state { return port }
        return nil
    }

    func url(token: String, name: String) -> URL? {
        port.flatMap { URL(string: "http://127.0.0.1:\($0)/\(token)/\(name)") }
    }

    func start() async throws {
        if isRunning { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listenerBox.withLock { $0 = listener }
        stateBox.withLock { $0 = .starting }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Locked(false)
            func resumeOnce(_ body: () -> Void) -> Bool {
                let first = resumed.withLock { value -> Bool in
                    defer { value = true }
                    return !value
                }
                if first { body() }
                return first
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    self.stateBox.withLock { $0 = .ready(port) }
                    Logger.shared.info(.server, "listening", ["port": .init(Int(port))])
                    _ = resumeOnce { continuation.resume() }
                case .failed(let error):
                    self.stateBox.withLock { $0 = .failed(String(describing: error)) }
                    Logger.shared.error(.server, "listener failed", ["error": .init(String(describing: error))])
                    if !resumeOnce({ continuation.resume(throwing: error) }) { self.onStop?() }
                case .cancelled:
                    self.stateBox.withLock { $0 = .stopped }
                    Logger.shared.warn(.server, "listener stopped")
                    if !resumeOnce({ continuation.resume(throwing: CancellationError()) }) { self.onStop?() }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listenerBox.withLock { listener in
            listener?.cancel()
            listener = nil
        }
        let open = connections.withLock { value -> [NWConnection] in
            defer { value.removeAll() }
            return Array(value.values)
        }
        open.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections.withLock { $0[id] = connection }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.withLock { $0[id] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHead(connection, buffer: [])
    }

    private func receiveHead(_ connection: NWConnection, buffer: [UInt8]) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer += data }
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receiveHead(connection, buffer: buffer)
                }
            case .invalid:
                Task {
                    _ = await self.send(connection, HTTPResponseWriter.head(status: 400, headers: [("Content-Length", "0"), ("Connection", "close")]))
                    connection.cancel()
                }
            case .complete(let head, _):
                Task { await self.respond(connection, head) }
            }
        }
    }

    private func respond(_ connection: NWConnection, _ head: HTTPRequestHead) async {
        let started = Date()
        defer { connection.cancel() }
        switch router.route(head) {
        case .text(let status, let contentType, let body):
            let headBytes = HTTPResponseWriter.head(status: status, headers: [("Content-Type", contentType),
                                                                              ("Content-Length", "\(body.count)"), ("Connection", "close")])
            _ = await send(connection, headBytes + (head.method == "HEAD" ? [] : body))
            log(head, status: status, bytes: Int64(body.count), firstByteMs: nil, started: started)
        case .failure(let status, let headers):
            _ = await send(connection, HTTPResponseWriter.head(status: status, headers: headers + [("Content-Length", "0"), ("Connection", "close")]))
            log(head, status: status, bytes: 0, firstByteMs: nil, started: started)
        case .media(let status, let headers, let body):
            guard await send(connection, HTTPResponseWriter.head(status: status, headers: headers + [("Connection", "close")])) else { return }
            var sent: Int64 = 0
            var firstByteMs: Double?
            if head.method != "HEAD" {
                do {
                    for try await chunk in body {
                        if firstByteMs == nil { firstByteMs = Date().timeIntervalSince(started) * 1000 }
                        // Leaving the loop drops the stream, which cancels the engine's download.
                        guard await send(connection, chunk) else { break }
                        sent += Int64(chunk.count)
                    }
                } catch {
                    Logger.shared.warn(.server, "body failed", ["file": .init(String(head.path.split(separator: "/").last ?? "")),
                                                               "error": .init(String(describing: error)), "sent": .init(sent)])
                }
            }
            log(head, status: status, bytes: sent, firstByteMs: firstByteMs, started: started)
        }
    }

    private func send(_ connection: NWConnection, _ bytes: [UInt8]) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private func log(_ head: HTTPRequestHead, status: Int, bytes: Int64, firstByteMs: Double?, started: Date) {
        var fields: [String: LogValue] = [
            "file": .init(String(head.path.split(separator: "/").last ?? "")),
            "range": .init(head.headers["range"] ?? ""),
            "status": .init(status),
            "bytes": .init(bytes),
            "ms": .init((Date().timeIntervalSince(started) * 1000).rounded()),
        ]
        if let firstByteMs { fields["firstByteMs"] = .init(firstByteMs.rounded()) }
        Logger.shared.info(.server, head.method, fields)
    }
}
```

- [ ] **Step 3: Implement the direct-mode playlist loader**

`ios/Sources/App/Playback/DirectPlaylistLoader.swift`:

```swift
import AVFoundation
import BiliShared

/// Direct mode hands AVPlayer its playlists through a custom URL scheme instead of the local
/// server, so it still works when the server is what failed. Media URIs inside are the CDN's.
final class DirectPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "bilinative"
    let queue = DispatchQueue(label: "bilinative.direct-loader")
    private let entries = Locked<[String: [String: String]]>([:])

    func register(token: String, playlists: [String: String]) -> URL {
        entries.withLock { $0[token] = playlists }
        return URL(string: "\(Self.scheme)://\(token)/master.m3u8")!
    }

    func unregister(_ token: String) {
        entries.withLock { $0[token] = nil }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.scheme, let token = url.host,
              let text = entries.current[token]?[url.lastPathComponent] else { return false }
        loadingRequest.dataRequest?.respond(with: Data(text.utf8))
        loadingRequest.finishLoading()
        return true
    }
}
```

- [ ] **Step 4: Implement playback assembly**

`ios/Sources/App/Playback/PlaybackBuilder.swift`:

```swift
import Foundation
import BiliShared
import BiliAPI
import DashHLS
import Ripper
import LocalHTTP

enum PlaybackError: Error, Equatable {
    case noSidx
    case codecUnplayable(String)
    case noTrack
    case serverDown

    var userMessage: String {
        switch self {
        case .noSidx: return "视频索引无法解析"
        case .codecUnplayable: return "这个编码无法播放，正在换一种"
        case .noTrack: return "没有可播放的清晰度"
        case .serverDown: return "本地加速服务不可用"
        }
    }
}

struct PreparedTrack {
    let stream: DashStream
    /// Bytes 0 through the end of the SIDX, with the init segment already patched when needed.
    let headers: [UInt8]
    let totalSize: Int64
    let segments: [MediaSegment]
    var initRange: ByteRange { stream.initialization }
}

struct PreparedPlayback {
    let video: PreparedTrack
    let audio: PreparedTrack
    /// True when the served init segment was renamed from hev1 to hvc1.
    let rewroteHEV1: Bool
}

enum PlaybackBuilder {
    static func prepare(choice: TrackChoice,
                        fetchHeaders: (TrackKind, DashStream) async throws -> (bytes: [UInt8], total: Int64)) async throws -> PreparedPlayback {
        func track(_ kind: TrackKind, _ stream: DashStream) async throws -> (PreparedTrack, Bool) {
            let fetched = try await fetchHeaders(kind, stream)
            guard let segments = SidxParser.parse(fetched.bytes, absoluteStart: 0) else { throw PlaybackError.noSidx }
            var headers = fetched.bytes
            var rewrote = false
            if kind == .video {
                switch InitSegmentFixer.fixHEV1(headers) {
                case .unchanged: break
                case .rewritten(let fixed):
                    headers = fixed
                    rewrote = true
                case .unplayable(let reason):
                    throw PlaybackError.codecUnplayable(reason)
                }
            }
            return (PreparedTrack(stream: stream, headers: headers, totalSize: fetched.total, segments: segments), rewrote)
        }
        let (video, rewrote) = try await track(.video, choice.video)
        let (audio, _) = try await track(.audio, choice.audio)
        return PreparedPlayback(video: video, audio: audio, rewroteHEV1: rewrote)
    }

    static func ripperAssets(_ prepared: PreparedPlayback, session: RipperSession) -> PlaybackAssets {
        let playlists = playlists(prepared, videoURI: "v.mp4", audioURI: "a.mp4", videoPlaylist: "v.m3u8", audioPlaylist: "a.m3u8",
                                  rewriteHEV1: prepared.rewroteHEV1)
        func resource(_ kind: TrackKind, _ track: PreparedTrack) -> MediaResource {
            MediaResource(totalSize: track.totalSize, prefix: track.headers) { range in session.read(kind, range) }
        }
        return PlaybackAssets(playlists: playlists, media: ["v.mp4": resource(.video, prepared.video), "a.mp4": resource(.audio, prepared.audio)])
    }

    /// AVPlayer reads Bilibili's original bytes in direct mode, so the codec string stays as given.
    static func directPlaylists(_ prepared: PreparedPlayback, token: String) -> [String: String] {
        let base = "\(DirectPlaylistLoader.scheme)://\(token)/"
        return playlists(prepared, videoURI: prepared.video.stream.baseURL, audioURI: prepared.audio.stream.baseURL,
                         videoPlaylist: base + "v.m3u8", audioPlaylist: base + "a.m3u8", rewriteHEV1: false)
    }

    private static func playlists(_ prepared: PreparedPlayback, videoURI: String, audioURI: String, videoPlaylist: String,
                                  audioPlaylist: String, rewriteHEV1: Bool) -> [String: String] {
        let video = prepared.video.stream
        let audio = prepared.audio.stream
        let variant = HLSVariant(codec: CodecMapper.video(codecs: video.codecs, qualityID: video.id, rewriteHEV1: rewriteHEV1),
                                 audioCodecs: audio.codecs.isEmpty ? "mp4a.40.2" : audio.codecs,
                                 averageBandwidth: video.bandwidth + audio.bandwidth,
                                 width: video.width, height: video.height, frameRate: CodecMapper.frameRate(video.frameRate))
        return [
            "master.m3u8": PlaylistBuilder.master(variant, videoPlaylist: videoPlaylist, audioPlaylist: audioPlaylist),
            "v.m3u8": PlaylistBuilder.media(HLSTrack(uri: videoURI, initRange: prepared.video.initRange, segments: prepared.video.segments)),
            "a.m3u8": PlaylistBuilder.media(HLSTrack(uri: audioURI, initRange: prepared.audio.initRange, segments: prepared.audio.segments)),
        ]
    }

    /// One plain request per track, Bilibili's own address first, then its backups.
    static func directHeaders(_ stream: DashStream, transport: RangeTransport) async throws -> (bytes: [UInt8], total: Int64) {
        guard let range = ByteRange(start: 0, end: stream.indexRange.end) else { throw PlaybackError.noSidx }
        var lastError: Error = PlaybackError.noTrack
        for address in [stream.baseURL] + stream.backupURLs {
            guard let url = URL(string: address) else { continue }
            do {
                let response = try await transport.fetch(url, range: range)
                guard response.status == 206, let total = ContentRange.parse(response.headers["content-range"])?.total else {
                    throw RipperError.badResponse(status: response.status)
                }
                var bytes: [UInt8] = []
                for try await chunk in response.body { bytes += chunk }
                guard Int64(bytes.count) == range.length else { throw RipperError.lengthMismatch(got: Int64(bytes.count), expected: range.length) }
                return (bytes, total)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
```

- [ ] **Step 5: Push and check CI**

```bash
git add ios
git commit -m "Add local HLS server, direct-mode playlist loader and playback assembly"
git push
```

Expected: "iOS compile check" green with `LocalServerTests` passing.

---

### Task 25: Playback controller (modes, fallbacks, codec memory, stats)

**Files:**
- Create: `ios/Sources/App/Playback/PlaybackController.swift`, `ios/Sources/App/Playback/CodecMemory.swift`, `ios/Sources/App/Playback/OverlayStats.swift`
- Replace: `ios/Sources/App/AppEnvironment.swift` (full version below)
- Test: `ios/Tests/AppTests/CodecMemoryTests.swift`

**Interfaces:**
- Consumes: Task 24; `BiliClient`, `PlayURLInfo`, `TrackSelector`, `VideoCodec`, `BiliError` (BiliAPI); `RipperSession`, `RipperConfig`, `AutoConcurrency`, `NodeMode`, `MediaURLPolicy`, `URLSessionRangeTransport`, `RipperStats` (Ripper); `Logger`.
- Produces:
  - `protocol PlayURLProvider: Sendable { func playURL(quality: Int) async throws -> PlayURLInfo }`, `BiliPlayURLProvider(client:bvid:cid:)`.
  - `struct PlaybackEnvironment` (`provider`, `router`, `server`, `directLoader`, `transport`, `auto`, `nodeMode`, `policy`, `ripperConfig`, `codecMemory`, `mediaHeaders`).
  - `CodecMemory(defaults:)` with `order(preferred:) -> [VideoCodec]`, `markFailed(_ kind: String)`, `excludesDolby`, `reset()`.
  - `OverlayStats` (`firstFrameMs`, `lastSeekMs`, `stalls`, `downloadBps`, `ripper: RipperStats?`).
  - `@MainActor @Observable PlaybackController(environment:quality:codec:btrEnabled:)` with `player`, `mode` (`.ripper`, `.direct`, `.directFallback`; `label`), `phase` (`.idle`, `.loading`, `.playing`, `.failed(String)`), `qualities`, `selectedQuality`, `codec`, `btrEnabled`, `overlay`, `start(at:) async`, `setBTR(_:) async`, `setQuality(_:) async`, `setCodec(_:) async`, `stop()`, `debugKillServer()` (DEBUG).
  - Full `AppEnvironment` adding `auto`, `router`, `server`, `directLoader`, `transport`, `codecMemory`, `startServices() async`, `playbackEnvironment(bvid:cid:) -> PlaybackEnvironment`.

Fallback order, as the spec's section 10 says: a failing BTR session first refreshes its signed URLs once, then switches to direct mode at the current position; an AVPlayer item failure in BTR mode switches to direct mode; an item failure in direct mode marks the codec as failed and restarts with the next codec; when no codec is left the screen shows a message.

- [ ] **Step 1: Write the codec memory test**

`ios/Tests/AppTests/CodecMemoryTests.swift`:

```swift
import XCTest
@testable import BiliNative

final class CodecMemoryTests: XCTestCase {
    func testFailedKindsMoveToTheBackAndDolbyIsExcluded() {
        let memory = CodecMemory(defaults: UserDefaults(suiteName: "codec-\(UUID().uuidString)")!)
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["av1", "hevc", "avc"])
        memory.markFailed("av1")
        XCTAssertEqual(memory.order(preferred: .av1).map(\.rawValue), ["hevc", "avc"])
        XCTAssertFalse(memory.excludesDolby)
        memory.markFailed("dolby")
        XCTAssertTrue(memory.excludesDolby)
        memory.reset()
        XCTAssertEqual(memory.order(preferred: .hevc).map(\.rawValue), ["hevc", "av1", "avc"])
    }
}
```

- [ ] **Step 2: Implement codec memory and overlay stats**

`ios/Sources/App/Playback/CodecMemory.swift`:

```swift
import Foundation
import BiliAPI

/// Codec kinds AVPlayer refused on this phone, so they are not tried first again.
final class CodecMemory: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "playback.failedCodecs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var failed: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func order(preferred: VideoCodec) -> [VideoCodec] {
        let fallback: [VideoCodec] = [.hevc, .av1, .avc]
        let order = [preferred] + fallback.filter { $0 != preferred }
        return order.filter { !failed.contains($0.rawValue) }
    }

    var excludesDolby: Bool { failed.contains("dolby") }

    func markFailed(_ kind: String) {
        defaults.set(Array(failed.union([kind])).sorted(), forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
```

`ios/Sources/App/Playback/OverlayStats.swift`:

```swift
import Ripper

struct OverlayStats: Equatable {
    var firstFrameMs: Double?
    var lastSeekMs: Double?
    var stalls = 0
    var downloadBps: Double = 0
    var ripper: RipperStats?
}
```

- [ ] **Step 3: Implement the controller**

`ios/Sources/App/Playback/PlaybackController.swift`:

```swift
import AVFoundation
import Foundation
import Observation
import UIKit
import BiliShared
import BiliAPI
import Ripper
import LocalHTTP
import DevLog

protocol PlayURLProvider: Sendable {
    func playURL(quality: Int) async throws -> PlayURLInfo
}

struct BiliPlayURLProvider: PlayURLProvider {
    let client: BiliClient
    let bvid: String
    let cid: Int64

    func playURL(quality: Int) async throws -> PlayURLInfo {
        try await client.playURL(bvid: bvid, cid: cid, quality: quality)
    }
}

struct PlaybackEnvironment {
    let provider: PlayURLProvider
    let router: PlaybackRouter
    let server: LocalServer
    let directLoader: DirectPlaylistLoader
    let transport: RangeTransport
    let auto: AutoConcurrency
    let nodeMode: NodeMode
    let policy: MediaURLPolicy
    let ripperConfig: RipperConfig
    let codecMemory: CodecMemory
    let mediaHeaders: [String: String]
}

@MainActor
@Observable
final class PlaybackController {
    enum Mode: Equatable {
        case ripper, direct, directFallback

        var label: String {
            switch self {
            case .ripper: return "BTR"
            case .direct: return "直连"
            case .directFallback: return "直连（回退）"
            }
        }
    }

    enum Phase: Equatable {
        case idle, loading, playing
        case failed(String)
    }

    let player = AVPlayer()
    private(set) var mode: Mode = .ripper
    private(set) var phase: Phase = .idle
    private(set) var qualities: [QualityOption] = []
    private(set) var selectedQuality: Int
    private(set) var codec: VideoCodec
    private(set) var btrEnabled: Bool
    private(set) var overlay = OverlayStats()

    @ObservationIgnored private let environment: PlaybackEnvironment
    @ObservationIgnored private var session: RipperSession?
    @ObservationIgnored private var routerToken: String?
    @ObservationIgnored private var directToken: String?
    @ObservationIgnored private var choice: TrackChoice?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var seekStartedAt: Date?
    @ObservationIgnored private var refreshedAfterFatal = false
    @ObservationIgnored private var lastDelivered: Int64 = 0
    @ObservationIgnored private var switching = false

    init(environment: PlaybackEnvironment, quality: Int, codec: VideoCodec, btrEnabled: Bool) {
        self.environment = environment
        selectedQuality = quality
        self.codec = codec
        self.btrEnabled = btrEnabled
        player.automaticallyWaitsToMinimizeStalling = true
        environment.server.onStop = { [weak self] in
            Task { @MainActor in await self?.serverStopped() }
        }
    }

    var currentSeconds: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // MARK: public actions

    func start(at time: Double = 0) async {
        phase = .loading
        startedAt = Date()
        overlay = OverlayStats()
        refreshedAfterFatal = false
        do {
            let info = try await environment.provider.playURL(quality: selectedQuality)
            qualities = info.qualityOptions
            guard let dash = info.dash else { throw BiliError.notDash }
            guard let choice = TrackSelector.choose(dash, quality: selectedQuality, codecOrder: environment.codecMemory.order(preferred: codec),
                                                    excludeDolbyVision: environment.codecMemory.excludesDolby) else {
                throw PlaybackError.noTrack
            }
            self.choice = choice
            Logger.shared.info(.player, "choice", ["quality": .init(choice.video.id), "codecs": .init(choice.video.codecs),
                                                   "audio": .init(choice.audio.id), "node": .init(NodeCatalog.nodeKey(of: choice.video.baseURL)),
                                                   "btr": .init(btrEnabled)])
            if btrEnabled && environment.server.isRunning {
                try await startRipper(choice, at: time)
            } else {
                try await startDirect(choice, at: time, fallback: btrEnabled)
            }
            scheduleRefresh(for: choice)
        } catch PlaybackError.codecUnplayable(let reason) {
            Logger.shared.warn(.player, "codec unplayable", ["reason": .init(reason)])
            await nextCodec(at: time)
        } catch {
            fail(error)
        }
    }

    func setBTR(_ enabled: Bool) async {
        Logger.shared.info(.ui, "btr switch", ["on": .init(enabled)])
        btrEnabled = enabled
        await restart()
    }

    func setQuality(_ quality: Int) async {
        Logger.shared.info(.ui, "quality", ["id": .init(quality)])
        selectedQuality = quality
        await restart()
    }

    func setCodec(_ codec: VideoCodec) async {
        Logger.shared.info(.ui, "codec", ["codec": .init(codec.rawValue)])
        self.codec = codec
        await restart()
    }

    func stop() {
        refreshTask?.cancel()
        statsTask?.cancel()
        player.pause()
        detachObservers()
        player.replaceCurrentItem(with: nil)
        teardownSession()
        if let directToken { environment.directLoader.unregister(directToken) }
        directToken = nil
        phase = .idle
    }

    #if DEBUG
    func debugKillServer() {
        environment.server.stop()
    }
    #endif

    // MARK: modes

    private func startRipper(_ choice: TrackChoice, at time: Double) async throws {
        let session = RipperSession(sources: [.video: (choice.video.baseURL, choice.video.backupURLs),
                                              .audio: (choice.audio.baseURL, choice.audio.backupURLs)],
                                    mode: environment.nodeMode, config: environment.ripperConfig, transport: environment.transport,
                                    auto: environment.auto, policy: environment.policy)
        session.onFatal = { [weak self] error in
            Task { @MainActor in await self?.ripperFailed(error) }
        }
        do {
            let prepared = try await PlaybackBuilder.prepare(choice: choice) { kind, stream in
                let headers = try await session.loadHeaders(kind, through: stream.indexRange.end)
                return (headers.bytes, headers.totalSize)
            }
            session.setSegments(.video, prepared.video.segments)
            session.setSegments(.audio, prepared.audio.segments)
            let token = environment.router.register(PlaybackBuilder.ripperAssets(prepared, session: session))
            guard let url = environment.server.url(token: token, name: "master.m3u8") else { throw PlaybackError.serverDown }
            teardownSession()
            self.session = session
            routerToken = token
            mode = .ripper
            try await load(url: url, viaLoader: false, at: time)
        } catch let error as PlaybackError where error != .serverDown {
            session.close()
            throw error
        } catch {
            session.close()
            Logger.shared.warn(.player, "btr start failed, going direct", ["error": .init(String(describing: error))])
            try await startDirect(choice, at: time, fallback: true)
        }
    }

    private func startDirect(_ choice: TrackChoice, at time: Double, fallback: Bool) async throws {
        let transport = environment.transport
        let prepared = try await PlaybackBuilder.prepare(choice: choice) { _, stream in
            try await PlaybackBuilder.directHeaders(stream, transport: transport)
        }
        teardownSession()
        if let directToken { environment.directLoader.unregister(directToken) }
        let token = PlaybackRouter.makeToken()
        directToken = token
        let url = environment.directLoader.register(token: token, playlists: PlaybackBuilder.directPlaylists(prepared, token: token))
        mode = fallback ? .directFallback : .direct
        try await load(url: url, viaLoader: true, at: time)
    }

    private func load(url: URL, viaLoader: Bool, at time: Double) async throws {
        detachObservers()
        // AVURLAssetHTTPHeaderFieldsKey is not in the public headers; AVFoundation honours it for the CDN requests of direct mode.
        let options: [String: Any]? = viaLoader ? ["AVURLAssetHTTPHeaderFieldsKey": environment.mediaHeaders] : nil
        let asset = AVURLAsset(url: url, options: options)
        if viaLoader { asset.resourceLoader.setDelegate(environment.directLoader, queue: environment.directLoader.queue) }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        attachObservers(item)
        player.replaceCurrentItem(with: item)
        if time > 0 {
            await player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        startStatsLoop()
        Logger.shared.info(.player, "load", ["mode": .init(mode.label), "at": .init(time)])
    }

    // MARK: failures

    private func ripperFailed(_ error: Error) async {
        guard mode == .ripper, let choice else { return }
        if !refreshedAfterFatal {
            refreshedAfterFatal = true
            Logger.shared.warn(.player, "btr range failed, refreshing urls", ["error": .init(String(describing: error))])
            await refreshURLs(for: choice)
            return
        }
        await fallBackToDirect(reason: "btr failed again")
    }

    private func serverStopped() async {
        guard mode == .ripper else { return }
        await fallBackToDirect(reason: "local server stopped")
    }

    private func fallBackToDirect(reason: String) async {
        guard !switching, let choice else { return }
        switching = true
        defer { switching = false }
        let time = currentSeconds
        Logger.shared.warn(.player, "fallback to direct", ["reason": .init(reason), "at": .init(time)])
        do {
            try await startDirect(choice, at: time, fallback: true)
        } catch {
            fail(error)
        }
    }

    private func itemFailed(_ error: Error?) async {
        Logger.shared.error(.player, "item failed", ["mode": .init(mode.label), "error": .init(String(describing: error))])
        if mode == .ripper {
            await fallBackToDirect(reason: "item failed in btr mode")
        } else {
            await nextCodec(at: currentSeconds)
        }
    }

    private func nextCodec(at time: Double) async {
        guard let choice else { return fail(PlaybackError.noTrack) }
        let kind = TrackSelector.codecKind(choice.video)
        environment.codecMemory.markFailed(kind)
        Logger.shared.warn(.player, "codec failed", ["kind": .init(kind)])
        guard !environment.codecMemory.order(preferred: codec).isEmpty else {
            return fail(PlaybackError.codecUnplayable("all"))
        }
        await start(at: time)
    }

    private func fail(_ error: Error) {
        let message = (error as? BiliError)?.userMessage ?? (error as? PlaybackError)?.userMessage ?? "播放失败：\(error.localizedDescription)"
        phase = .failed(message)
        Logger.shared.error(.player, "failed", ["error": .init(String(describing: error))])
    }

    // MARK: signed URL refresh

    private func scheduleRefresh(for choice: TrackChoice) {
        refreshTask?.cancel()
        guard let deadline = URLComponents(string: choice.video.baseURL)?.queryItems?.first(where: { $0.name == "deadline" })?.value
            .flatMap(Double.init) else { return }
        let wait = max(30, deadline - Date().timeIntervalSince1970 - 300)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self, let choice = self.choice else { return }
            await self.refreshURLs(for: choice)
        }
    }

    private func refreshURLs(for choice: TrackChoice) async {
        do {
            let info = try await environment.provider.playURL(quality: selectedQuality)
            guard let dash = info.dash,
                  let video = dash.video.first(where: { $0.id == choice.video.id && $0.codecid == choice.video.codecid }),
                  let audio = dash.audio.first(where: { $0.id == choice.audio.id }) else { return }
            session?.replaceURLs(.video, primary: video.baseURL, backups: video.backupURLs)
            session?.replaceURLs(.audio, primary: audio.baseURL, backups: audio.backupURLs)
            self.choice = TrackChoice(video: video, audio: audio)
            scheduleRefresh(for: TrackChoice(video: video, audio: audio))
        } catch {
            Logger.shared.warn(.player, "url refresh failed", ["error": .init(String(describing: error))])
        }
    }

    // MARK: observers and stats

    private func attachObservers(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            let reason = player.reasonForWaitingToPlay
            Task { @MainActor in self?.timeControlChanged(status, reason: reason) }
        })
        observations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            Task { @MainActor in await self?.itemFailed(error) }
        })
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.timeJumpedNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timeJumped() }
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in await self?.itemFailed(error) }
        })
        notificationTokens.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.session?.dropCache()
                Logger.shared.warn(.player, "memory warning, prefetch cache dropped")
            }
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification, object: item, queue: .main) { _ in
            guard let event = item.errorLog()?.events.last else { return }
            Logger.shared.warn(.player, "error log", ["status": .init(event.errorStatusCode), "domain": .init(event.errorDomain),
                                                      "comment": .init(event.errorComment ?? ""), "uri": .init(event.uri ?? "")])
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.newAccessLogEntryNotification, object: item, queue: .main) { _ in
            guard let event = item.accessLog()?.events.last else { return }
            Logger.shared.info(.player, "access log", ["indicatedBitrate": .init(event.indicatedBitrate.rounded()),
                                                       "observedBitrate": .init(event.observedBitrate.rounded()),
                                                       "stalls": .init(event.numberOfStalls),
                                                       "transferMs": .init((event.transferDuration * 1000).rounded())])
        })
    }

    private func detachObservers() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
    }

    private func tick(_ time: CMTime) {
        guard let session, let item = player.currentItem else { return }
        let seconds = time.seconds.isFinite ? time.seconds : 0
        session.updatePlayhead(seconds: seconds, rate: Double(player.rate))
        let ahead = item.loadedTimeRanges.map(\.timeRangeValue)
            .first { $0.start.seconds <= seconds + 0.5 && $0.end.seconds >= seconds }
            .map { $0.end.seconds - seconds } ?? 0
        session.reportBuffer(aheadSeconds: ahead, playing: player.timeControlStatus == .playing)
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus, reason: AVPlayer.WaitingReason?) {
        switch status {
        case .playing:
            if overlay.firstFrameMs == nil {
                overlay.firstFrameMs = Date().timeIntervalSince(startedAt) * 1000
                Logger.shared.info(.player, "first frame", ["ms": .init(overlay.firstFrameMs!.rounded()), "mode": .init(mode.label)])
            }
            if let seekStartedAt {
                overlay.lastSeekMs = Date().timeIntervalSince(seekStartedAt) * 1000
                Logger.shared.info(.player, "seek resumed", ["ms": .init(overlay.lastSeekMs!.rounded())])
                self.seekStartedAt = nil
            }
            phase = .playing
        case .waitingToPlayAtSpecifiedRate:
            if reason == .toMinimizeStalls, overlay.firstFrameMs != nil, seekStartedAt == nil {
                overlay.stalls += 1
                session?.reportStall()
                Logger.shared.warn(.player, "stall", ["at": .init(currentSeconds.rounded()), "mode": .init(mode.label)])
            }
        default:
            break
        }
    }

    private func timeJumped() {
        guard overlay.firstFrameMs != nil else { return }
        seekStartedAt = Date()
        Logger.shared.info(.player, "seek", ["to": .init(currentSeconds.rounded())])
    }

    private func startStatsLoop() {
        statsTask?.cancel()
        lastDelivered = 0
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                let stats = self.session?.stats()
                let delivered = stats?.deliveredBytes ?? 0
                self.overlay.downloadBps = Double(max(0, delivered - self.lastDelivered)) * 2
                self.lastDelivered = delivered
                self.overlay.ripper = stats
            }
        }
    }

    // MARK: helpers

    private func restart() async {
        let time = currentSeconds
        stop()
        await start(at: time)
    }

    private func teardownSession() {
        session?.close()
        session = nil
        if let routerToken { environment.router.unregister(routerToken) }
        routerToken = nil
    }
}
```

- [ ] **Step 4: Replace the environment with the full version**

`ios/Sources/App/AppEnvironment.swift`:

```swift
import Foundation
import Observation
import WebKit
import BiliAPI
import Ripper
import LocalHTTP
import DevLog

@MainActor
@Observable
final class AppEnvironment {
    enum Account: Equatable {
        case unknown
        case loggedOut
        case loggedIn(name: String, vip: Bool)
        /// Cookies exist but Bilibili no longer accepts them.
        case expired
    }

    let settings = AppSettings()
    private(set) var account: Account = .unknown
    @ObservationIgnored let cookies: CookieJar
    @ObservationIgnored let client: BiliClient
    @ObservationIgnored let auto = AutoConcurrency()
    @ObservationIgnored let router = PlaybackRouter()
    @ObservationIgnored let server: LocalServer
    @ObservationIgnored let directLoader = DirectPlaylistLoader()
    @ObservationIgnored let transport = URLSessionRangeTransport(headers: BiliClient.mediaHeaders)
    @ObservationIgnored let codecMemory = CodecMemory()

    init() {
        cookies = CookieJar(KeychainStore.loadCookies())
        cookies.onChange = { KeychainStore.saveCookies($0) }
        client = BiliClient(transport: URLSessionHTTPTransport(), cookies: cookies)
        server = LocalServer(router: router)
    }

    func startServices() async {
        do {
            try await server.start()
        } catch {
            Logger.shared.error(.server, "server did not start; playback will use direct mode", ["error": .init(String(describing: error))])
        }
    }

    func playbackEnvironment(bvid: String, cid: Int64) -> PlaybackEnvironment {
        PlaybackEnvironment(provider: BiliPlayURLProvider(client: client, bvid: bvid, cid: cid), router: router, server: server,
                            directLoader: directLoader, transport: transport, auto: auto, nodeMode: settings.nodeChoice.mode,
                            policy: .bilibili, ripperConfig: RipperConfig(), codecMemory: codecMemory, mediaHeaders: BiliClient.mediaHeaders)
    }

    func refreshAccount() async {
        do {
            try await client.ensureRiskCookies()
            let nav = try await client.nav()
            if nav.isLogin {
                account = .loggedIn(name: nav.uname ?? "", vip: nav.isVip)
                Logger.shared.info(.app, "account", ["user": .init(nav.mid.map(Redactor.mid) ?? "?"), "vip": .init(nav.isVip)])
            } else {
                account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired
            }
        } catch {
            Logger.shared.warn(.app, "nav failed", ["error": .init(String(describing: error))])
            if account == .unknown { account = cookies.value("SESSDATA") == nil ? .loggedOut : .expired }
        }
    }

    func didLogin(_ webCookies: [String: String]) async {
        var merged = cookies.all
        merged.merge(webCookies) { _, new in new }
        cookies.replaceAll(merged)
        await refreshAccount()
    }

    func logout() async {
        cookies.removeAll()
        KeychainStore.deleteCookies()
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        account = .loggedOut
    }
}
```

In `BiliNativeApp.swift`, start the server once: add `.task { await env.startServices() }` after `.environment(env)`. Also configure the audio session there so playback continues in the background and in picture in picture:

```swift
import AVFoundation
import SwiftUI

@main
struct BiliNativeApp: App {
    @State private var env = AppEnvironment()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .task { await env.startServices() }
        }
    }
}
```

- [ ] **Step 5: Push and check CI**

```bash
git add ios
git commit -m "Add playback controller with BTR, direct fallback, codec memory and URL refresh"
git push
```

Expected: green, `CodecMemoryTests` pass. The controller is exercised end to end in Task 28.

---

### Task 26: Home, player screen, controls and stats overlay

**Files:**
- Create: `ios/Sources/App/Home/HomeView.swift`, `ios/Sources/App/Home/RecentStore.swift`, `ios/Sources/App/Player/PlayerScreen.swift`, `ios/Sources/App/Player/VideoPlayerView.swift`, `ios/Sources/App/Player/StatsOverlay.swift`
- Modify: `ios/Sources/App/RootView.swift` (becomes a thin wrapper around `HomeView`), `ios/Sources/App/AppEnvironment.swift` (add `recents`)
- Test: `ios/Tests/AppTests/RecentStoreTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment`, `PlaybackController`, `LinkParser`, `BiliError`, `VideoView`, `VideoPage`, `VideoCodec`, `QualityOption`.
- Produces: `PlayerRoute` (`bvid`, `cid`, `title`, `part`, `page`, `pageCount`; `Hashable`, `Codable`, `Identifiable`); `RecentStore(defaults:)` with `items`, `add(_:)`, `clear()`; `HomeView`; `PlayerScreen(route:)`; `VideoPlayerView(player:)`; `StatsOverlay(stats:mode:)`.

- [ ] **Step 1: Write the recents test**

`ios/Tests/AppTests/RecentStoreTests.swift`:

```swift
import XCTest
@testable import BiliNative

@MainActor
final class RecentStoreTests: XCTestCase {
    func testNewestFirstWithoutDuplicatesAndCapped() {
        let defaults = UserDefaults(suiteName: "recents-\(UUID().uuidString)")!
        let store = RecentStore(defaults: defaults)
        for index in 0..<35 {
            store.add(PlayerRoute(bvid: "BV\(index)", cid: Int64(index), title: "t\(index)", part: "", page: 1, pageCount: 1))
        }
        store.add(PlayerRoute(bvid: "BV3", cid: 3, title: "t3", part: "", page: 1, pageCount: 1))
        XCTAssertEqual(store.items.count, 30)
        XCTAssertEqual(store.items.first?.bvid, "BV3")
        XCTAssertEqual(store.items.filter { $0.bvid == "BV3" }.count, 1)
        XCTAssertEqual(RecentStore(defaults: defaults).items.first?.bvid, "BV3")
    }
}
```

- [ ] **Step 2: Implement recents and the route**

`ios/Sources/App/Home/RecentStore.swift`:

```swift
import Foundation
import Observation

struct PlayerRoute: Hashable, Codable, Identifiable {
    let bvid: String
    let cid: Int64
    let title: String
    let part: String
    let page: Int
    let pageCount: Int

    var id: String { "\(bvid)#\(cid)" }
}

@MainActor
@Observable
final class RecentStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "home.recents"
    private(set) var items: [PlayerRoute]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([PlayerRoute].self, from: $0) } ?? []
    }

    func add(_ route: PlayerRoute) {
        items.removeAll { $0.id == route.id }
        items.insert(route, at: 0)
        if items.count > 30 { items.removeLast(items.count - 30) }
        defaults.set(try? JSONEncoder().encode(items), forKey: key)
    }

    func clear() {
        items = []
        defaults.removeObject(forKey: key)
    }
}
```

Add to `AppEnvironment` (next to `settings`): `let recents = RecentStore()`.

- [ ] **Step 3: Implement the home screen**

`ios/Sources/App/Home/HomeView.swift`:

```swift
import SwiftUI
import BiliAPI
import DevLog

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var manualText = ""
    @State private var opening = false
    @State private var errorText: String?
    @State private var partChoice: VideoView?
    @State private var route: PlayerRoute?
    @State private var showLogin = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section("账号") { AccountRow(showLogin: $showLogin) }
                Section("打开视频") {
                    PasteButton(payloadType: String.self) { strings in
                        Task { await open(strings.first ?? "") }
                    }
                    HStack {
                        TextField("粘贴链接、BV 号或分享文字", text: $manualText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { Task { await open(manualText) } }
                        Button("打开") { Task { await open(manualText) } }
                            .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
                if !env.recents.items.isEmpty {
                    Section("最近打开") {
                        ForEach(env.recents.items) { item in
                            Button { route = item } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(2).foregroundStyle(.primary)
                                    if item.pageCount > 1 {
                                        Text("P\(item.page) \(item.part)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(AppInfo.displayName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .navigationDestination(item: $route) { PlayerScreen(route: $0) }
            .sheet(isPresented: $showLogin) { LoginView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .confirmationDialog("选择分P", isPresented: Binding(get: { partChoice != nil }, set: { if !$0 { partChoice = nil } }),
                                presenting: partChoice) { view in
                ForEach(view.pages, id: \.cid) { page in
                    Button("P\(page.page) \(page.part)") { go(view, page) }
                }
            }
            .overlay { if opening { ProgressView().controlSize(.large) } }
            .task { await env.refreshAccount() }
        }
    }

    private func open(_ text: String) async {
        errorText = nil
        guard let link = LinkParser.parse(text) else {
            errorText = BiliError.invalidLink.userMessage
            return
        }
        opening = true
        defer { opening = false }
        do {
            let (view, page) = try await env.client.resolve(link)
            Logger.shared.info(.ui, "open", ["bvid": .init(view.bvid), "pages": .init(view.pages.count)])
            if let page, let match = view.pages.first(where: { $0.page == page }) {
                go(view, match)
            } else if view.pages.count > 1 {
                partChoice = view
            } else if let first = view.pages.first {
                go(view, first)
            } else {
                errorText = BiliError.notDash.userMessage
            }
            manualText = ""
        } catch {
            errorText = (error as? BiliError)?.userMessage ?? error.localizedDescription
        }
    }

    private func go(_ view: VideoView, _ page: VideoPage) {
        partChoice = nil
        let next = PlayerRoute(bvid: view.bvid, cid: page.cid, title: view.title, part: page.part, page: page.page, pageCount: view.pages.count)
        env.recents.add(next)
        route = next
    }
}
```

In `ios/Sources/App/RootView.swift`, replace only the `RootView` struct with the one below; the `AccountRow` struct from Task 23 stays in the file unchanged:

```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        HomeView()
    }
}
```

- [ ] **Step 4: Implement the player screen**

`ios/Sources/App/Player/VideoPlayerView.swift`:

```swift
import AVKit
import SwiftUI

struct VideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
```

`ios/Sources/App/Player/StatsOverlay.swift`:

```swift
import SwiftUI

struct StatsOverlay: View {
    let stats: OverlayStats
    let mode: PlaybackController.Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line("模式", mode.label)
            line("首帧", stats.firstFrameMs.map { String(format: "%.2f 秒", $0 / 1000) } ?? "-")
            line("跳转恢复", stats.lastSeekMs.map { String(format: "%.2f 秒", $0 / 1000) } ?? "-")
            line("卡顿", "\(stats.stalls) 次")
            line("下载", String(format: "%.1f MB/s", stats.downloadBps / 1_048_576))
            if let ripper = stats.ripper {
                line("连接", "\(ripper.concurrency)  重复 \(String(format: "%.1f", ripper.duplicateShare * 100))%  缓存命中 \(ripper.cacheHits)")
                ForEach(ripper.nodes, id: \.node) { node in
                    let state = ripper.nodeStates.first { $0.node == node.node }
                    Text("\(shortName(node.node)) \(Int(node.firstByteMs))ms \(String(format: "%.1f", (state?.bps ?? 0) / 1_048_576))MB/s \(state?.state ?? "")")
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .padding(6)
        .allowsHitTesting(false)
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text("\(label) \(value)")
    }

    private func shortName(_ node: String) -> String {
        node.replacingOccurrences(of: ".bilivideo.com", with: "").replacingOccurrences(of: "upos-sz-", with: "")
    }
}
```

`ios/Sources/App/Player/PlayerScreen.swift`:

```swift
import SwiftUI
import BiliAPI

struct PlayerScreen: View {
    let route: PlayerRoute
    @Environment(AppEnvironment.self) private var env
    @State private var controller: PlaybackController?

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                VideoPlayerView(player: controller.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        if env.settings.showOverlay { StatsOverlay(stats: controller.overlay, mode: controller.mode) }
                    }
                PlayerControls(controller: controller)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 220)
            }
            Spacer(minLength: 0)
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            let settings = env.settings
            let next = PlaybackController(environment: env.playbackEnvironment(bvid: route.bvid, cid: route.cid),
                                          quality: settings.preferredQuality, codec: settings.preferredCodec, btrEnabled: settings.btrEnabled)
            controller = next
            await next.start()
        }
        .onDisappear { controller?.stop() }
    }
}

struct PlayerControls: View {
    let controller: PlaybackController
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings
        List {
            if case .failed(let message) = controller.phase {
                Text(message).foregroundStyle(.red)
                Button("重试") { Task { await controller.start(at: controller.currentSeconds) } }
            }
            Picker("清晰度", selection: Binding(get: { controller.selectedQuality }, set: { quality in
                settings.preferredQuality = quality
                Task { await controller.setQuality(quality) }
            })) {
                ForEach(controller.qualities, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker("编码", selection: Binding(get: { controller.codec }, set: { codec in
                settings.preferredCodec = codec
                Task { await controller.setCodec(codec) }
            })) {
                ForEach(VideoCodec.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("BTR 加速", isOn: Binding(get: { controller.btrEnabled }, set: { enabled in
                settings.btrEnabled = enabled
                Task { await controller.setBTR(enabled) }
            }))
            Toggle("显示统计", isOn: $settings.showOverlay)
        }
        .listStyle(.insetGrouped)
    }
}
```

- [ ] **Step 5: Add a settings stub**

`HomeView` opens `SettingsView`, which Task 27 builds. Add a stub now so this task compiles:

`ios/Sources/App/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack { Text("设置") }
    }
}
```

- [ ] **Step 6: Push and check CI**

```bash
git add ios
git commit -m "Add home screen, player screen, controls and stats overlay"
git push
```

Expected: green; `RecentStoreTests` pass; the first-launch screenshot shows the home screen with the paste button.

---

### Task 27: Settings, node mode and dev log streaming to the PC

**Files:**
- Create: `ios/Sources/App/DevTools/DevLogSetup.swift`, `ios/Sources/App/DevTools/LogPoster.swift`, `ios/Sources/App/DevTools/LogServerDiscovery.swift`, `ios/Sources/App/DevTools/DeviceInfo.swift`
- Replace: `ios/Sources/App/Settings/SettingsView.swift`
- Modify: `ios/Sources/App/BiliNativeApp.swift` (install logging at launch)
- Test: `ios/Tests/AppTests/LogPosterTests.swift`

**Interfaces:**
- Consumes: `FileSink`, `NetworkSink`, `AckStore`, `ReplayPlanner`, `Logger` (DevLog); `AppSettings`.
- Produces:
  - `DevLogSetup.install()` (file sink, always), `DevLogSetup.apply(_ settings: AppSettings)` (network sink when enabled; DEV_TOOLS only), `DevLogSetup.exportFile() -> URL?`, `DevLogSetup.networkState() -> String`.
  - `LogTarget` (`service(name:)`, `manual(host:port:)`; `init?(settings:)`), `LogPoster(target:)` with `post(_ body: Data) async throws`.
  - `LogServerDiscovery` (`services`, `start()`, `stop()`).
  - `DeviceInfo.fields() -> [String: LogValue]`, `DeviceInfo.watchNetwork()` (logs Wi-Fi/cellular changes).

- [ ] **Step 1: Write the poster test**

The poster speaks HTTP over Network.framework. The test points it at the app's own `LocalServer`, which answers a POST with 405, to prove the request goes out and a non-200 answer becomes an error. The 200 path is verified on the phone against the real PC receiver (Task 29).

`ios/Tests/AppTests/LogPosterTests.swift`:

```swift
import XCTest
@testable import BiliNative

final class LogPosterTests: XCTestCase {
    func testNon200AnswerIsAnError() async throws {
        let server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
        defer { server.stop() }
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: server.port!))
        do {
            try await poster.post(Data("{}\n".utf8))
            XCTFail("expected an error for a 405 answer")
        } catch LogPoster.Failure.status(let line) {
            XCTAssertTrue(line.contains("405"))
        }
    }

    func testUnreachableTargetFailsFast() async {
        let poster = LogPoster(target: .manual(host: "127.0.0.1", port: 9))
        let started = Date()
        do {
            try await poster.post(Data("{}\n".utf8))
            XCTFail("expected an error")
        } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
```

- [ ] **Step 2: Implement the poster and discovery**

`ios/Sources/App/DevTools/LogPoster.swift`:

```swift
import Foundation
import Network
import BiliShared

enum LogTarget: Equatable {
    case service(name: String)
    case manual(host: String, port: UInt16)

    @MainActor
    init?(settings: AppSettings) {
        if !settings.logServerService.isEmpty {
            self = .service(name: settings.logServerService)
            return
        }
        let parts = settings.logServerManual.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), !parts[0].isEmpty else { return nil }
        self = .manual(host: String(parts[0]), port: port)
    }

    var endpoint: NWEndpoint {
        switch self {
        case .service(let name):
            return .service(name: name, type: "_bilinative-log._tcp", domain: "local.", interface: nil)
        case .manual(let host, let port):
            return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 47321)
        }
    }
}

/// One short HTTP/1.1 POST per batch over Network.framework, which also reaches Bonjour services
/// without resolving them to an address first.
final class LogPoster: @unchecked Sendable {
    enum Failure: Error {
        case connect(String)
        case status(String)
    }

    let target: LogTarget
    private let queue = DispatchQueue(label: "bilinative.log-poster")

    init(target: LogTarget) {
        self.target = target
    }

    func post(_ body: Data) async throws {
        let connection = NWConnection(to: target.endpoint, using: .tcp)
        defer { connection.cancel() }
        try await ready(connection)
        let head = "POST /logs HTTP/1.1\r\nHost: bilinative-log\r\nContent-Type: application/x-ndjson\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        try await send(connection, Data(head.utf8) + body)
        let reply = try await receive(connection)
        let statusLine = String(decoding: reply.prefix(64), as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        guard statusLine.contains(" 200 ") else { throw Failure.status(statusLine) }
    }

    private func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Locked(false)
            func finish(_ result: Result<Void, Error>) {
                let first = resumed.withLock { value -> Bool in
                    defer { value = true }
                    return !value
                }
                if first { continuation.resume(with: result) }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let error): finish(.failure(Failure.connect(String(describing: error))))
                case .waiting(let error): finish(.failure(Failure.connect(String(describing: error))))
                case .cancelled: finish(.failure(Failure.connect("cancelled")))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(.failure(Failure.connect("timeout"))) }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data ?? Data()) }
            }
        }
    }
}
```

`ios/Sources/App/DevTools/LogServerDiscovery.swift`:

```swift
import Foundation
import Network
import Observation

@MainActor
@Observable
final class LogServerDiscovery {
    private(set) var services: [String] = []
    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_bilinative-log._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint { return name }
                return nil
            }
            Task { @MainActor in self?.services = Array(Set(names)).sorted() }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
```

`ios/Sources/App/DevTools/DeviceInfo.swift`:

```swift
import Foundation
import Network
import UIKit
import DevLog

enum DeviceInfo {
    private static var monitor: NWPathMonitor?

    /// A Wi-Fi to cellular switch mid-playback explains a burst of failed pieces in the logs.
    @MainActor
    static func watchNetwork() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let type = path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
            Logger.shared.info(.app, "network", ["type": .init(type), "up": .init(path.status == .satisfied)])
        }
        monitor.start(queue: DispatchQueue(label: "bilinative.network"))
        self.monitor = monitor
    }

    @MainActor
    static func fields() -> [String: LogValue] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ["app": .init(AppInfo.version), "ios": .init(UIDevice.current.systemVersion), "model": .init(model)]
    }
}
```

- [ ] **Step 3: Implement the logging setup**

`ios/Sources/App/DevTools/DevLogSetup.swift`:

```swift
import Foundation
import DevLog

@MainActor
enum DevLogSetup {
    private static var fileSink: FileSink?
    private static var networkSink: NetworkSink?
    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("logs")
    }

    /// The on-phone log is always kept (last 20 MB), so the export button works even without a PC.
    static func install() {
        guard fileSink == nil else { return }
        if let sink = try? FileSink(directory: directory, session: Logger.shared.session) {
            Logger.shared.add(sink)
            fileSink = sink
        }
        Logger.shared.info(.app, "launch", DeviceInfo.fields())
        DeviceInfo.watchNetwork()
    }

    static func apply(_ settings: AppSettings) {
        #if DEV_TOOLS
        if let networkSink {
            networkSink.stop()
            Logger.shared.remove(networkSink)
        }
        networkSink = nil
        guard settings.logServerEnabled, let target = LogTarget(settings: settings) else { return }
        let poster = LogPoster(target: target)
        let sink = NetworkSink(poster: { try await poster.post($0) })
        let ack = AckStore(url: directory.appendingPathComponent("ack.json"))
        sink.onAcknowledged = { session, seq in ack.record(session, seq) }
        if let fileSink {
            // Whatever an earlier (perhaps crashed) session never got to the PC goes first.
            sink.enqueue(ReplayPlanner.unsent(files: fileSink.sessionFiles(), currentSession: Logger.shared.session, ack: ack))
        }
        Logger.shared.add(sink)
        sink.start()
        networkSink = sink
        Logger.shared.info(.app, "log server on", ["target": .init(String(describing: target))])
        #endif
    }

    static func networkState() -> String {
        guard let networkSink else { return "未开启" }
        switch networkSink.state {
        case .idle: return "连接中…"
        case .connected: return "已连接，待发送 \(networkSink.pending) 条"
        case .failing(let reason): return "连不上：\(reason)"
        }
    }

    static func exportFile() -> URL? {
        try? fileSink?.exportFile()
    }
}
```

In `BiliNativeApp.swift`, call logging setup first thing:

```swift
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        DevLogSetup.install()
    }
```

and add `.task { DevLogSetup.apply(env.settings) }` next to the existing `.task { await env.startServices() }`.

- [ ] **Step 4: Implement the settings screen**

Replace `ios/Sources/App/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = LogServerDiscovery()
    @State private var networkState = ""
    @State private var exportURL: URL?

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section("加速") {
                    Picker("CDN 节点", selection: $settings.nodeChoice) {
                        ForEach(AppSettings.NodeChoice.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("BTR 加速（默认）", isOn: $settings.btrEnabled)
                    Button("重置编码记忆") { env.codecMemory.reset() }
                }
                #if DEV_TOOLS
                Section {
                    Toggle("发送日志到电脑", isOn: $settings.logServerEnabled)
                    if settings.logServerEnabled {
                        ForEach(discovery.services, id: \.self) { name in
                            Button {
                                settings.logServerService = name
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    if settings.logServerService == name { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        TextField("或手动输入 IP:端口", text: $settings.logServerManual)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { settings.logServerService = "" }
                        Text(networkState).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let exportURL {
                        ShareLink("导出日志文件", item: exportURL)
                    } else {
                        Button("准备导出日志") { exportURL = DevLogSetup.exportFile() }
                    }
                } header: {
                    Text("开发者")
                } footer: {
                    Text("在电脑上运行 uv run tools/logserver.py，手机和电脑连同一个 Wi-Fi。")
                }
                #endif
                Section {
                    LabeledContent("版本", value: AppInfo.version)
                    Text("下载加速移植自 Bilibili 线程撕裂者（BTR），MIT 许可。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
            .onChange(of: settings.logServerEnabled) { DevLogSetup.apply(settings) }
            .onChange(of: settings.logServerService) { DevLogSetup.apply(settings) }
            .onChange(of: settings.logServerManual) { DevLogSetup.apply(settings) }
            .task {
                while !Task.isCancelled {
                    networkState = DevLogSetup.networkState()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
}
```

Add a CI screenshot of this screen: in `.github/workflows/ios-compile.yml`, after the `shoot()` function definition, add `shoot 02-settings 8 -DemoScreen settings`, and in `HomeView` add, inside `.task`, before `await env.refreshAccount()`:

```swift
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-DemoScreen"),
                   let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-DemoScreen"),
                   ProcessInfo.processInfo.arguments.dropFirst(index + 1).first == "settings" {
                    showSettings = true
                }
                #endif
```

- [ ] **Step 5: Push and check CI**

```bash
git add ios .github
git commit -m "Add settings screen and dev log streaming to the PC"
git push
```

Expected: green; `LogPosterTests` pass; `02-settings.png` shows the 开发者 section.

---

### Task 28: Simulator integration test (real AVPlayer through BTR and the fallback)

**Files:**
- Create: `ios/scripts/make_test_media.py`
- Modify: `ios/Sources/App/DebugSupport/DebugSupport.swift` (add `FakeCDNServer`, `FixtureMedia`, `FixturePlayback`)
- Create: `ios/Tests/AppTests/PlaybackIntegrationTests.swift`
- Modify: `.github/workflows/ios-compile.yml` (generate media, pass it to the tests)

**Interfaces:**
- Consumes: everything from Tasks 24-25; `HTTPRequestParser`, `HTTPResponseWriter`, `RangeRequest` (LocalHTTP); `NodeAddress`, `NodeMode`, `MediaURLPolicy` (Ripper); `DashStream`, `Dash`, `PlayURLInfo` (BiliAPI).
- Produces (DEBUG only): `FakeCDNServer(directory:)` (`start() async throws -> UInt16`, `stop()`, `requestCount`); `FixtureMedia.load(directory:variant:) throws -> FixtureMedia`; `FixturePlayback.make(media:codecid:ports:server:router:loader:) -> PlaybackEnvironment`.

The test media is two DASH files per variant (video, audio) with a SIDX, like Bilibili's: one H.264 variant and one HEVC variant forced to the `hev1` tag so the init fix is exercised.

- [ ] **Step 1: Write the media generator**

`ios/scripts/make_test_media.py`:

```python
"""Builds Bilibili-like DASH test media (separate video/audio files with a sidx) with ffmpeg.

Usage: python make_test_media.py OUTPUT_DIR
Writes avc-video.mp4, avc-audio.mp4, hevc-video.mp4, hevc-audio.mp4 and meta.json.
"""
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

VARIANTS = {
    "avc": ["-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p"],
    "hevc": ["-c:v", "libx265", "-tag:v", "hev1", "-pix_fmt", "yuv420p", "-x265-params", "log-level=error"],
}


def boxes(data):
    offset = 0
    while offset + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if size == 1:
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
        if size < 8:
            break
        yield kind.decode("latin-1"), offset, size
        offset += size


def ranges(path):
    data = path.read_bytes()
    found = {kind: (offset, size) for kind, offset, size in boxes(data)}
    if "moov" not in found or "sidx" not in found:
        raise SystemExit(f"{path.name}: expected moov and sidx, found {sorted(found)}")
    moov_offset, moov_size = found["moov"]
    sidx_offset, sidx_size = found["sidx"]
    return {
        "initialization": f"0-{moov_offset + moov_size - 1}",
        "indexRange": f"{sidx_offset}-{sidx_offset + sidx_size - 1}",
        "size": len(data),
    }


def build(variant, codec_args, out):
    with tempfile.TemporaryDirectory() as work:
        work = pathlib.Path(work)
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
            "-t", "40", "-map", "0:v", "-map", "1:a",
            *codec_args, "-g", "60", "-keyint_min", "60", "-sc_threshold", "0",
            "-c:a", "aac", "-b:a", "128k",
            "-f", "dash", "-single_file", "1", "-single_file_name", f"{variant}-$RepresentationID$.mp4",
            "-seg_duration", "2", str(work / f"{variant}.mpd"),
        ], check=True)
        manifest = ET.parse(work / f"{variant}.mpd").getroot()
        ns = {"d": "urn:mpeg:dash:schema:mpd:2011"}
        reps = {rep.get("id"): rep for rep in manifest.iterfind(".//d:Representation", ns)}
        result = {}
        for rep_id, rep in reps.items():
            kind = "video" if rep.get("width") else "audio"
            target = out / f"{variant}-{kind}.mp4"
            shutil.copy(work / f"{variant}-{rep_id}.mp4", target)
            result[kind] = {
                "file": target.name,
                "codecs": rep.get("codecs"),
                "bandwidth": int(rep.get("bandwidth")),
                "width": int(rep.get("width") or 0),
                "height": int(rep.get("height") or 0),
                **ranges(target),
            }
        result["duration"] = 40
        return result


def main():
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    meta = {variant: build(variant, args, out) for variant, args in VARIANTS.items()}
    (out / "meta.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
```

If ffmpeg's dash muxer puts the sidx somewhere `ranges()` does not expect, the script stops with the box list it found; fix the muxer flags rather than the check.

- [ ] **Step 2: Add the debug fixtures to the app**

Append to `ios/Sources/App/DebugSupport/DebugSupport.swift`, inside the existing `#if DEBUG` block (add the imports at the top of the file: `import Network`, `import BiliAPI`, `import Ripper`):

```swift
/// Serves files from a directory with Range support, like a CDN node, on 127.0.0.1.
final class FakeCDNServer: @unchecked Sendable {
    let directory: URL
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "bilinative.fake-cdn")
    private let counter = Locked(0)

    init(directory: URL) {
        self.directory = directory
    }

    var requestCount: Int { counter.current }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.serve(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Locked(false)
            listener.stateUpdateHandler = { state in
                let first = resumed.withLock { value -> Bool in
                    defer { value = true }
                    return !value
                }
                guard first else { return }
                switch state {
                case .ready: continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error): continuation.resume(throwing: error)
                default: resumed.withLock { $0 = false }
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, case .complete(let head, _) = HTTPRequestParser.parse([UInt8](data)) else {
                connection.cancel()
                return
            }
            self.counter.withLock { $0 += 1 }
            let name = String(head.path.split(separator: "/").last ?? "")
            guard let content = try? Data(contentsOf: self.directory.appendingPathComponent(name)) else {
                connection.send(content: Data(HTTPResponseWriter.head(status: 404, headers: [("Content-Length", "0")])),
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let total = Int64(content.count)
            guard case .range(let range) = RangeRequest.parse(head.headers["range"], totalSize: total) else {
                connection.send(content: Data(HTTPResponseWriter.head(status: 416, headers: [("Content-Length", "0")])),
                                completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let body = content.subdata(in: Int(range.start)..<Int(range.end + 1))
            let headBytes = HTTPResponseWriter.head(status: 206, headers: [
                ("Content-Type", "video/mp4"), ("Content-Length", "\(body.count)"),
                ("Content-Range", "bytes \(range.start)-\(range.end)/\(total)"), ("Connection", "close"),
            ])
            connection.send(content: Data(headBytes) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

struct FixtureMedia {
    struct Track: Decodable {
        let file: String
        let codecs: String
        let bandwidth: Int
        let width: Int
        let height: Int
        let initialization: String
        let indexRange: String
        let size: Int
    }

    let video: Track
    let audio: Track

    static func load(directory: URL, variant: String) throws -> FixtureMedia {
        let data = try Data(contentsOf: directory.appendingPathComponent("meta.json"))
        let all = try JSONDecoder().decode([String: [String: AnyDecodableTrack]].self, from: data)
        guard let entry = all[variant], let video = entry["video"]?.track, let audio = entry["audio"]?.track else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return FixtureMedia(video: video, audio: audio)
    }

    /// meta.json mixes track objects with a plain "duration" number.
    struct AnyDecodableTrack: Decodable {
        let track: Track?
        init(from decoder: Decoder) throws {
            track = try? Track(from: decoder)
        }
    }
}

struct FixtureProvider: PlayURLProvider {
    let info: PlayURLInfo
    func playURL(quality: Int) async throws -> PlayURLInfo { info }
}

enum FixturePlayback {
    /// A PlaybackEnvironment whose "Bilibili" is the fixture media on the fake CDN nodes at `ports`.
    static func make(media: FixtureMedia, codecid: Int, ports: [UInt16], server: LocalServer, router: PlaybackRouter,
                     loader: DirectPlaylistLoader) -> PlaybackEnvironment {
        func stream(_ track: FixtureMedia.Track, id: Int, codecid: Int) -> DashStream {
            DashStream(id: id, baseURL: "http://127.0.0.1:\(ports[0])/\(track.file)?deadline=4102444800",
                       backupURLs: ports.dropFirst().map { "http://127.0.0.1:\($0)/\(track.file)?deadline=4102444800" },
                       bandwidth: track.bandwidth, mimeType: "video/mp4", codecs: track.codecs, codecid: codecid,
                       width: track.width, height: track.height, frameRate: "30",
                       initialization: ByteRange.parse(track.initialization)!, indexRange: ByteRange.parse(track.indexRange)!)
        }
        let dash = Dash(duration: 40, video: [stream(media.video, id: 64, codecid: codecid)], audio: [stream(media.audio, id: 30280, codecid: 0)])
        let info = PlayURLInfo(quality: 64, acceptQuality: [64], acceptDescription: ["测试 720P"], dash: dash, hasDurl: false)
        var config = RipperConfig()
        config.fixedConcurrency = 8
        return PlaybackEnvironment(provider: FixtureProvider(info: info), router: router, server: server, directLoader: loader,
                                   transport: URLSessionRangeTransport(), auto: AutoConcurrency(),
                                   nodeMode: .custom(ports.map { NodeAddress(host: "127.0.0.1", port: Int($0)) }),
                                   policy: .any, ripperConfig: config, codecMemory: CodecMemory(defaults: UserDefaults(suiteName: "fixture-\(UUID().uuidString)")!),
                                   mediaHeaders: [:])
    }
}
```

- [ ] **Step 3: Write the integration tests**

`ios/Tests/AppTests/PlaybackIntegrationTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import BiliNative

@MainActor
final class PlaybackIntegrationTests: XCTestCase {
    private var mediaDirectory: URL!
    private var nodes: [FakeCDNServer] = []
    private var server: LocalServer!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["MEDIA_DIR"] else {
            throw XCTSkip("MEDIA_DIR not set; CI generates it with ios/scripts/make_test_media.py")
        }
        mediaDirectory = URL(fileURLWithPath: path)
        nodes = [FakeCDNServer(directory: mediaDirectory), FakeCDNServer(directory: mediaDirectory)]
        server = LocalServer(router: DebugSupport.makeRouter())
        try await server.start()
    }

    override func tearDown() async throws {
        nodes.forEach { $0.stop() }
        server?.stop()
    }

    private func makeController(variant: String, codecid: Int, btr: Bool) async throws -> PlaybackController {
        var ports: [UInt16] = []
        for node in nodes { ports.append(try await node.start()) }
        let media = try FixtureMedia.load(directory: mediaDirectory, variant: variant)
        let environment = FixturePlayback.make(media: media, codecid: codecid, ports: ports, server: server, router: server.router,
                                               loader: DirectPlaylistLoader())
        return PlaybackController(environment: environment, quality: 64, codec: codecid == 12 ? .hevc : .avc, btrEnabled: btr)
    }

    private func waitUntil(_ seconds: Double, _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTFail("timed out")
    }

    func testBTRPlaysAndSeeks() async throws {
        let controller = try await makeController(variant: "avc", codecid: 7, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertNotNil(controller.overlay.firstFrameMs)
        await controller.player.seek(to: CMTime(seconds: 20, preferredTimescale: 600))
        try await waitUntil(60) { controller.currentSeconds >= 23 }
        XCTAssertEqual(controller.mode, .ripper)
        XCTAssertGreaterThan(nodes.map(\.requestCount).filter { $0 > 0 }.count, 1, "both fake nodes should have served pieces")
        controller.stop()
    }

    func testHEV1VideoPlaysThroughTheInitFix() async throws {
        let controller = try await makeController(variant: "hevc", codecid: 12, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .ripper)
        controller.stop()
    }

    func testFallsBackToDirectWhenTheServerDies() async throws {
        let controller = try await makeController(variant: "avc", codecid: 7, btr: true)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 3 }
        controller.debugKillServer()
        try await waitUntil(30) { controller.mode == .directFallback }
        let resumedAt = controller.currentSeconds
        try await waitUntil(60) { controller.currentSeconds >= resumedAt + 5 }
        controller.stop()
    }

    func testDirectModePlays() async throws {
        let controller = try await makeController(variant: "avc", codecid: 7, btr: false)
        await controller.start()
        try await waitUntil(60) { controller.currentSeconds >= 5 }
        XCTAssertEqual(controller.mode, .direct)
        controller.stop()
    }
}
```

- [ ] **Step 4: Generate the media in CI and pass it to the tests**

In `.github/workflows/ios-compile.yml`, add before "Build and test on the simulator":

```yaml
      - name: Test media
        run: |
          brew install ffmpeg
          python3 ios/scripts/make_test_media.py "$RUNNER_TEMP/media"
```

and add this line to the `xcodebuild … test` step's environment (xcodebuild passes `TEST_RUNNER_`-prefixed variables to the tests without the prefix):

```yaml
        env:
          TEST_RUNNER_MEDIA_DIR: ${{ runner.temp }}/media
```

- [ ] **Step 5: Push and make CI green**

```bash
git add ios .github
git commit -m "Add simulator playback integration tests with fake CDN nodes"
git push
```

Run: `gh run watch`.
Expected: all four integration tests pass. These are the most likely to need iteration; read the test log, the `[server]`/`[player]` lines and the crash reports in the artifact before changing anything. If the HEVC test fails because the simulator cannot decode HEVC, keep the test but mark it `throw XCTSkip("simulator lacks HEVC decode")` only after confirming that from AVPlayer's error log entry, and note it for the phone checklist.

---

### Task 29: First TestFlight build and KaiC's phone checklist

**Files:**
- Create: `docs/m1-phone-checklist.md`

- [ ] **Step 1: Upload to TestFlight**

Per the ios-testflight skill: on `main`, run `python scripts/testflight.py start` with upload on. Wait for App Store Connect processing and for the build to appear in TestFlight for KaiC.

- [ ] **Step 2: Write the checklist**

`docs/m1-phone-checklist.md`:

```markdown
# Milestone 1: phone checklist

Before you start: on the PC run `uv run tools/logserver.py` (allow Python on private networks if Windows asks). Phone and PC on the same Wi-Fi.

1. Install the build from TestFlight and open it.
2. Settings (gear) → 开发者 → turn on "发送日志到电脑". Allow "find devices on your local network" when iOS asks. Pick your PC from the list (or type the IP:port the PC printed). The status line should say 已连接 and the PC window should start printing lines.
3. Tap 登录哔哩哔哩 and log in the way you normally do. The account row should show your name and 大会员.
4. In the official app, open a video you know stutters (cold, 4K or high bitrate), tap Share → Copy link. In BiliNative tap Paste. The video should start.
5. With the stats overlay on, write down: 首帧 (first frame), then seek three times into parts not loaded yet and write down 跳转恢复 each time, and the 卡顿 count after about two minutes.
6. Turn off "BTR 加速" in the player and repeat step 5 on the same video.
7. Do steps 4-6 for two more videos.
8. For the same three videos, time the official app with a stopwatch: tap to first frame, and one seek.
9. Try picture in picture (swipe home while playing), the lock screen controls, and rotating to landscape full screen.
10. Tell Claude when you are done; the logs are already on the PC in `logs/`.
```

- [ ] **Step 3: Hand over to KaiC**

Send the checklist (SendUserFile) and tell KaiC the build is in TestFlight. Do not mark milestone 1 done until KaiC has run it and the numbers are read from `logs/` and compared against the success criteria in the spec (section 5). Then write the result (numbers per video, BTR vs direct vs official app) into `docs/m1-results.md` and commit it.

```bash
git add docs/m1-phone-checklist.md
git commit -m "Add milestone 1 phone checklist"
git push
```

---
