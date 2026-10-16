# BiliNative

A native Swift iOS client for Bilibili that looks and feels like the official app, with a Swift port of the
Bilibili Thread Ripper (BTR) multi-node download engine underneath. Built screen by screen in milestones.
Display name BiliFast and the pink Bolt icon (concept 2), picked by KaiC on 2026-10-16; the repo, folder and Xcode target keep the working name BiliNative.

## Read before working

1. `docs/superpowers/specs/2026-10-16-m1-playback-core-design.md`: the approved milestone 1 design (what and why).
2. `docs/superpowers/plans/2026-10-16-m1-playback-core.md`: the implementation plan, 29 tasks with full code.
3. `docs/official-app-reference.md`: what each official-app screen looks like (KaiC's screenshots, kept in
   `local/official-app-reference/`, gitignored). Read it, and the matching image, before building any screen.
4. `docs/background.md`: how the project got here, prior art, and what real Bilibili CDN nodes do. Read it
   before tuning the engine or debugging slow playback.

## Status

- 2026-10-16: spec approved, plan written and committed.
- 2026-10-16: milestone 1 built (Tasks 1-28, subagent-driven, every task reviewed, then a whole-branch review).
  Beyond the plan: ban scoping and damaged-span avoidance for Akamai (see `docs/background.md`, "Deviations
  from BTR"), direct mode falls back to backup URLs, and the overlay shows the codec and bitrate actually playing.
- PC speed test (2026-10-16, KaiC's playurl, overseas): 1080P+ HEVC 8.55 MB/s with BTR vs 0.98 MB/s on one
  connection.
- 2026-10-16: build 1 on the phone: full screen crashed, the first BTR video after a long background fell back
  to direct (iOS took the server's socket silently), and 卡顿 counted the wait after a drag. All three fixed for
  build 2. First phone impression: BTR starts almost instantly and never stalled while playing untouched; direct
  stalled for 18 s on the same video.
- 2026-10-16: milestone 1 verdict **go** (`docs/m1-results.md`). On 4 videos tried in both modes BTR started
  faster and stalled far less; KaiC calls it way better than the official app. Weak spots: a cold 4K start took
  8.7 s, and the first seconds after a jump into unloaded 4K can stall. That is the trigger for hurry mode.
- 2026-10-16: hurry mode built in the engine (node stats, placement by expected finish, small pieces, faster
  second and third copies, busy nodes not struck, adopted prefetches kept; `docs/background.md`, "Hurry mode"),
  with the 卡顿 window widened to 0.75 s. Phone retest pending.
- 2026-10-17: the build 3 phone log showed Akamai given 48-61 requests for URLSession's 8 connections while the
  mirrors sat idle (38 first-byte timeouts, two stalls). Full nodes are now skipped outside hurry mode too, Akamai
  is full at 8 from the start, and each copy picks its node once it holds a connection (`docs/background.md`,
  "Deviations from BTR"). From the same log: in a hurry later copies go to the node expected to finish first, an
  unmeasured node that trickles is held to the best known one, and connections lost at one moment are one strike
  (Akamai had been banned by two -1005s 2 ms apart). Not yet on the phone.
- 2026-10-17: milestone 2 spec and plan (`docs/superpowers/specs/2026-10-17-m2-video-page-design.md`,
  `docs/superpowers/plans/2026-10-17-m2-video-page.md`, 27 tasks in two builds). Build A (Tasks 1-15: the
  official-style player, gestures, full screen, PiP, panels, danmaku with settings, block words and sending) built
  in about 3 hours by parallel subagents, each task green in CI, batch-reviewed, then a whole-branch review.
  Shipped to TestFlight; phone test pending (`docs/m2-phone-checklist.md`, Build A). Deferred to build B: PiP
  that survives leaving the page, one AVPlayer per page (autoplay inside PiP), an owner token for
  `OrientationController` before stacked video pages.
- Next: KaiC's build A phone test, then build B (Tasks 16-27; KaiC adds the `BILI_APP_KEYS` secret first).
- Milestone 1 is a go/no-go gate: if BTR mode is not clearly faster than direct mode on KaiC's phone,
  stop before building more screens (spec section 5).
- Update this section when a task or milestone finishes.

## Rules for this repo

- The repo is public from the first push (free GitHub Actions Mac minutes). Never commit secrets, cookies,
  signed playurl responses or anything under `logs/` or `local/`.
- No code copied from ATV-Bilibili-demo (GPL-2.0) or PiliPlus (GPL-3.0); read them for endpoints and
  formats only. The BTR port keeps BTR's MIT notice (`ios/Packages/BiliCore/Sources/Ripper/LICENSE-BTR.txt`).
- No Bilibili logo or wordmark in the app; layout and colours may follow the official app.
- Borrowed art: PiliPlus's coin dialog images and icon font are committed in `ios/Resources/Borrowed/` (copied
  from PiliPlus at `bb2d86c`; KaiC's call on 2026-10-17, personal use). Whether to replace them is decided later,
  if the app is ever published. Nothing else from PiliPlus or Bilibili's app is copied in.
- UI text is Simplified Chinese.
- The network log sink is compiled only with `DEV_TOOLS` and never ships in a public release build.
- `ios/Packages/BiliCore` is Foundation-only, no third-party packages, Swift 5 language mode, and must build
  and pass `swift test` on Windows as well as macOS. Logic goes there whenever it does not need iOS.
- The app target is Swift 5 language mode, SwiftUI, no third-party dependencies, iOS 26 deployment target,
  built on GitHub's `macos-26` runners (newest Xcode on the image).
- Anything about building, signing or TestFlight: load the `ios-testflight` skill first.
- Code that hands a view to a system controller (AVPlayerViewController's full screen and content overlay, PiP,
  rotation, sheets) needs a simulator test that performs that transition, not only the inline screen. Build 1
  crashed on the full-screen button because AVKit moves its content overlay into another controller. M2 replaced
  AVKit's player with our own layer, so full screen is the same page rotated (`ios/Tests/AppTests/PlayerTransitionTests.swift`).
  Never make a hosting controller a child of a system controller whose views that controller may move.
- Hurry mode (deferred in the spec) is built, justified by the phone logs (`docs/m1-results.md`); the rules and
  files are in `docs/background.md`, "Hurry mode". `RipperConfig.hurry` switches it off.

## How to test

- Engine and everything else in the package, on the PC: `swift test --package-path ios/Packages/BiliCore`
- PC log receiver: `python -m unittest discover -s tools -p "test_*.py"`
- Live speed test from the PC: `swift run --package-path ios/Packages/BiliCore ripper-bench --bv BV… --mb 8`
  (Task 20). If Bilibili refuses API calls from the PC, save a playurl response from the browser to
  `local/playurl.json` (gitignored) and pass `--playurl local/playurl.json`.
- App code, compile only, on the PC: `bash tools/check-app.sh` (PowerShell: `tools\check-app.ps1`). It
  builds the app target and AppTests for the iOS simulator in WSL with xtool's iOS SDK and prints only
  compiler errors with repo paths; about 35 s cold, a few seconds after small edits. `--warnings`,
  `--release` (no `DEBUG`), `--device`, `--app-only`, `--repo DIR` (default: the checkout holding the
  current folder, so it works from any worktree). Run it before every push that touches `ios/`.
  It does not run tests, build assets/xcstrings/Info.plist or sign, and it compiles with Xcode 27.1
  (Swift 6.4) while CI uses Xcode 26.6 (Swift 6.3), so CI stays the gate. Warnings show only for files
  recompiled in that run. Setup and the manifest it compiles with: `tools/app-check/README.md`.
- App code, everything else: only in CI ("iOS compile check" workflow: simulator build, unit and integration
  tests, screenshots as the `simulator-screenshots` artifact). There is no Mac. On `main` and `m2` it also runs
  the BiliCore tests and a Release build; other branches skip both, since the PC already runs `swift test`.
  Debug builds take `-DemoData YES` (invented fixtures, no network or account) and `-DemoScreen <name>` to open
  any screen for screenshots; the `shoot` list in `.github/workflows/ios-compile.yml` names them all.
- On the phone: TestFlight build plus `docs/m1-phone-checklist.md` (M1) and `docs/m2-phone-checklist.md` (M2).

## Debugging from evidence

The app streams structured logs to the PC: KaiC runs `uv run tools/logserver.py`, turns on 设置 → 开发者 →
发送日志到电脑, and every event lands in `logs/<date>/<session>.jsonl`. Read those files before guessing:
they hold every API call, every engine piece (node, range, first byte, speed, outcome), every request
AVPlayer made to the in-app server, and AVPlayer's own access and error logs.

Crashes and hangs arrive the same way, as `app` events with message `crash` or `hang` (MetricKit, DEV_TOOLS only).
iOS hands a crash over on a later launch, so the events sit in that launch's session file, not the one that
crashed. A big stack is split into parts that share a `report` id (`part`/`parts`); join their `stack` fields in
order. Each frame reads `binary +offset (address)`, and the `binaries` lines give the UUIDs for symbolicating with
the build's dSYM. 设置 → 开发者 → 测试崩溃 crashes on purpose to check the path.

## Environment facts (KaiC's Windows PC)

- Swift 6.4.1 is installed at `D:\Tools\Swift` (PATH and SDKROOT are set in the User environment).
- Sideloadly must keep being started from `D:\Tools\Sideloadly\Sideloadly (Swift-safe).cmd`: Swift's
  `Foundation.dll` on PATH breaks Sideloadly's Apple login otherwise. Never put Sideloadly's `an\` folder
  on the system PATH (that breaks Swift instead).
- BTR's source, for reading the JS the engine is ported from: `D:\Repos\Apps\Bilibili-thread-ripper`.
  Always read it at the tag the port follows, not the working branch:
  `git -C D:\Repos\Apps\Bilibili-thread-ripper show 2026.10.8.1:src/idm-downloader.js`
  (or https://github.com/MrTangLuyao/Bilibili-thread-ripper/tree/2026.10.8.1/src).
- `swift test` on Windows prints a `wchar_t ... broken by a context change` warning from the WinSDK module a few times per run. It comes from the toolchain, not this repo; ignore it.

## Building and shipping

iOS app, developed on Windows with no Mac. GitHub Actions does everything:
`ios-compile.yml` compiles and screenshots on every push, and `testflight.yml` signs and
uploads when `scripts/testflight.py start` dispatches it. The full playbook, including
every manual step and known failures, is the global `ios-testflight` skill. Load it
before touching signing, `testflight.yml`, `ios/project.yml` or the compile workflow.

Identity: display name `BiliFast`, app target and scheme `BiliNative`, bundle id `com.kaichuan.bilifast`
(extensions: none). Repo `KaiC5504/BiliNative` (public). App Store Connect name:
`BiliFast`, Apple ID: `6823476667` (`ASC_APP_ID` in `testflight.yml`).

1. Work on `main` (this repo has no `dev` branch). Push. Wait for the compile check
   (`gh run list --limit 1`, then `gh run watch <id> --exit-status`), and look at the
   `simulator-screenshots` artifact for every screen you touched.
2. `python scripts/testflight.py start`, then `python scripts/testflight.py watch <id>` in
   the background. Green means Apple has processed the build. After any change to
   `testflight.yml`, run `start --dry-run` first.
3. Report the TestFlight build number, what changed and test steps for the phone.

The owner has authorised commit, push and Actions runs without asking. Never start a
signed build before the compile check is green.
