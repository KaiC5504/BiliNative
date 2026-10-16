# BiliNative

A native Swift iOS client for Bilibili that looks and feels like the official app, with a Swift port of the
Bilibili Thread Ripper (BTR) multi-node download engine underneath. Built screen by screen in milestones.
Display name BiliFast and the pink Bolt icon (concept 2), picked by KaiC on 2026-10-16; the repo, folder and Xcode target keep the working name BiliNative.

## Read before working

1. `docs/superpowers/specs/2026-10-16-m1-playback-core-design.md`: the approved milestone 1 design (what and why).
2. `docs/superpowers/plans/2026-10-16-m1-playback-core.md`: the implementation plan, 29 tasks with full code.
3. `docs/background.md`: how the project got here, prior art, and what real Bilibili CDN nodes do. Read it
   before tuning the engine or debugging slow playback.

## Status

- 2026-10-16: spec approved, plan written and committed.
- 2026-10-16: Task 1 done: `BiliShared` module in `ios/Packages/BiliCore`, "Core tests" CI workflow, public repo
  `KaiC5504/BiliNative`.
- Next: the plan is running subagent-driven (KaiC chose it on 2026-10-16), task by task from Task 2.
- Milestone 1 is a go/no-go gate: if BTR mode is not clearly faster than direct mode on KaiC's phone,
  stop before building more screens (spec section 5).
- Update this section when a task or milestone finishes.

## Rules for this repo

- The repo is public from the first push (free GitHub Actions Mac minutes). Never commit secrets, cookies,
  signed playurl responses or anything under `logs/` or `local/`.
- No code copied from ATV-Bilibili-demo (GPL-2.0) or PiliPlus (GPL-3.0); read them for endpoints and
  formats only. The BTR port keeps BTR's MIT notice (`ios/Packages/BiliCore/Sources/Ripper/LICENSE-BTR.txt`).
- No Bilibili logo or wordmark in the app; layout and colours may follow the official app.
- UI text is Simplified Chinese.
- The network log sink is compiled only with `DEV_TOOLS` and never ships in a public release build.
- `ios/Packages/BiliCore` is Foundation-only, no third-party packages, Swift 5 language mode, and must build
  and pass `swift test` on Windows as well as macOS. Logic goes there whenever it does not need iOS.
- The app target is Swift 5 language mode, SwiftUI, no third-party dependencies, iOS 26 deployment target,
  built on GitHub's `macos-26` runners (newest Xcode on the image).
- Anything about building, signing or TestFlight: load the `ios-testflight` skill first.
- Do not build the spec's deferred "hurry mode" unless the milestone 1 phone logs show startup or seeks are slow.

## How to test

- Engine and everything else in the package, on the PC: `swift test --package-path ios/Packages/BiliCore`
- PC log receiver: `python -m unittest discover -s tools -p "test_*.py"`
- Live speed test from the PC: `swift run --package-path ios/Packages/BiliCore ripper-bench --bv BV… --mb 8`
  (Task 20). If Bilibili refuses API calls from the PC, save a playurl response from the browser to
  `local/playurl.json` (gitignored) and pass `--playurl local/playurl.json`.
- App code: only in CI ("iOS compile check" workflow: core tests, simulator build, unit and integration
  tests, screenshots as the `simulator-screenshots` artifact). There is no Mac.
- On the phone: TestFlight build plus `docs/m1-phone-checklist.md` (Task 29).

## Debugging from evidence

The app streams structured logs to the PC: KaiC runs `uv run tools/logserver.py`, turns on 设置 → 开发者 →
发送日志到电脑, and every event lands in `logs/<date>/<session>.jsonl`. Read those files before guessing:
they hold every API call, every engine piece (node, range, first byte, speed, outcome), every request
AVPlayer made to the in-app server, and AVPlayer's own access and error logs.

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
`BiliNative`, Apple ID: `6823476667` (`ASC_APP_ID` in `testflight.yml`).

1. Work on `main` (this repo has no `dev` branch). Push. Wait for the compile check
   (`gh run list --limit 1`, then `gh run watch <id> --exit-status`), and look at the
   `simulator-screenshots` artifact for every screen you touched.
2. `python scripts/testflight.py start`, then `python scripts/testflight.py watch <id>` in
   the background. Green means Apple has processed the build. After any change to
   `testflight.yml`, run `start --dry-run` first.
3. Report the TestFlight build number, what changed and test steps for the phone.

The owner has authorised commit, push and Actions runs without asking. Never start a
signed build before the compile check is green.
