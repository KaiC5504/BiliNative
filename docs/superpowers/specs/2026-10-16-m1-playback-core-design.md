# BiliNative, milestone 1: playback core (design)

- Date: 2026-10-16
- Status: draft, waiting for KaiC's review
- Working name: BiliNative (the folder and repo get renamed once the real name is picked)

## 1. Why this exists

KaiC watches Bilibili from overseas on an iPhone. Cold and high-bitrate videos buffer badly.
On the PC, Bilibili Thread Ripper (BTR) fixes this by downloading each chunk from several
CDN nodes at once. iOS has no equivalent he is happy with:

- The PiliPlus forks with BTR built in (`lemonteaau/PiliPlus`, `nishuodedui1145-del/PiliPlus`)
  have the speed but are Flutter apps. KaiC tried them: they feel like the web version and
  much worse than the official app (rotation, layout, overall feel).
- The official app cannot be changed without a jailbreak. The only route into it is a
  VPN-style MITM proxy (`xirenjie0101/btr-ios` does this as a Loon script; its own real-device
  notes show the Loon script model is too limited to stream or cache properly).

So the plan is a native Swift iOS client that looks and feels like the official app, built
up screen by screen, with a BTR-style download engine underneath. Milestone 1 proves the
engine before any real screens are built.

## 2. Decisions already made

| Decision | Choice | Decided by |
|---|---|---|
| Platform | Native Swift app, no Flutter | KaiC |
| Device and OS | KaiC's phone: iPhone 17 Pro Max on iOS 27. Deployment target iOS 26, built with Xcode 26.6 (stable), so it also runs on other phones once public | KaiC |
| Audience | Private now, public later, so own name and icon, no copied code, no Bilibili logo | KaiC |
| Player | AVPlayer fed by an in-app HLS server that uses the BTR engine (option A), with direct CDN playback as automatic fallback (option C) | KaiC approved Claude's recommendation |
| Login | Bilibili's own web login page inside the app (password, SMS or QR) | Claude, KaiC asked for account login rather than QR only |
| First milestone | Playback core only, prove speed before UI | KaiC |
| Dev logging | App streams its logs to the PC over Wi-Fi | KaiC |
| UI language | Simplified Chinese, using a String Catalog so English can be added later | Claude (correct in review if wrong) |

## 3. Roadmap

Each milestone gets its own spec, plan and build.

1. **Playback core** (this document).
2. **Video page**: info, like/coin/favourite, related videos, comments, danmaku, rotate to full screen.
3. **Home feed and bottom tab bar.**
4. **Following feed (动态), my page (我的) with history and favourites, search**, in the order KaiC uses them.
5. Later: anime and films (PGC), downloads, live.

Milestone 1 is a gate. If BTR mode is not clearly better than direct mode on real videos,
the project stops before milestone 2.

## 4. Milestone 1 scope

In scope:

- **Login**: Bilibili's web login page in a `WKWebView`. When the `SESSDATA` cookie appears,
  the app copies the bilibili.com cookies into the Keychain and closes the page. A status line
  shows the account name and whether 大会员 is active. Log out clears the Keychain entry and
  the web view's cookie store.
- **Open a video**: a paste button (`PasteButton`, so iOS does not show the paste permission
  prompt) that accepts a BV id, av id, b23.tv short link or full video URL. A list of recently
  opened videos. A part picker for multi-part videos.
- **Play**: AVPlayer through the in-app HLS server. Quality picker up to what the account
  allows (4K, HDR, Dolby Vision with 大会员). Codec picker: HEVC, AV1, AVC. Audio: best AAC
  track. Background audio, picture in picture and lock-screen controls come from AVKit.
- **BTR switch**: on/off per playback, so the same video can be compared. Takes effect by
  reloading the item at the current position.
- **Stats overlay**: time to first frame, last seek-to-resume time, stall count, current
  download speed, per-node speed and first-byte time, duplicate-byte share, mode (BTR, direct,
  direct fallback).
- **Dev log streaming to the PC** (section 9).
- **Name and icon**: 3 to 5 icon concepts and name ideas for KaiC to choose from. The chosen
  icon ships in the first TestFlight build that has a real name; until then a placeholder.

Out of scope for milestone 1: video page, comments, danmaku, home feed, search, PGC
(anime/films), downloads, live, Dolby Atmos and Hi-Res audio, iPad layout, English UI.

## 5. Success criteria

1. KaiC can log in on the phone and play a 4K HDR video he has access to.
2. On 3 cold, high-bitrate videos chosen by KaiC, BTR mode beats direct mode on time to first
   frame and seek-to-resume, with no more stalls, using the overlay numbers.
3. On the same videos, BTR mode feels at least as good as the official app (KaiC's judgement,
   official app timed by stopwatch).
4. No broken playback: every failure in section 10 ends in slower playback, never a stuck
   player or an error screen, for the failures we can simulate in CI.

## 6. Architecture

### 6.1 Repository layout

```
BiliNative/
  project.yml              XcodeGen spec (per the ios-testflight skill)
  App/                     iOS app target (SwiftUI, iOS only)
  Packages/BiliCore/       Swift package, builds on Windows and iOS
    Sources/BiliAPI/       talking to Bilibili
    Sources/DashHLS/       SIDX parsing, HLS playlists, init segment fixes
    Sources/Ripper/        the BTR engine
    Sources/DevLog/        structured logger and its sinks
    Sources/ripper-bench/  command line speed test (Windows and macOS)
    Tests/                 unit and simulation tests
  tools/logserver.py       PC log receiver (uv script)
  logs/                    received logs, gitignored
  .github/workflows/       compile check, TestFlight
```

The split is about where things can be tested. Everything in `BiliCore` uses Foundation only
(FoundationNetworking on Windows), so `swift test` runs on the PC in seconds. Only the
`App` target needs a Mac, which means GitHub Actions.

### 6.2 BiliCore

**BiliAPI**
- `HTTPClient`: Foundation `URLSession`, Safari-like User-Agent, `Referer: https://www.bilibili.com`,
  cookie jar injected from outside (Keychain on iOS, a file path on the PC).
- Risk-control cookies: makes sure `buvid3`/`buvid4` exist (the website's fingerprint
  endpoint) before the first API call, because the web API answers 412 without them.
- WBI signing: fetches the img/sub keys from `nav`, caches them for the day, signs query strings.
- Endpoints for milestone 1: `x/web-interface/nav` (login state, 大会员, WBI keys),
  `x/web-interface/view` (BV/av to title, parts, cid), `x/player/wbi/playurl` with DASH flags
  (`fnval` covering DASH, HDR, 4K, Dolby Vision, 8K, AV1; `fourk=1`), b23.tv redirect resolution.
- Link parser: BV, av, b23.tv, `bilibili.com/video/...` with `?p=`.
- Models are `Codable` structs. Unknown fields are ignored so Bilibili adding fields never breaks parsing.

**DashHLS**
- SIDX parser: segment byte ranges and durations from the index box.
- Init/index fetch: the first bytes of each chosen representation (init segment plus SIDX),
  fetched through `Ripper` so the engine learns node speeds from the start.
- Playlist builder: master playlist (one video variant per chosen representation plus an
  AAC audio group, `CODECS`, `RESOLUTION`, `FRAME-RATE`, `VIDEO-RANGE`), media playlists with
  `EXT-X-MAP` and `EXT-X-BYTERANGE` per SIDX segment, `EXT-X-PLAYLIST-TYPE:VOD`.
- Codec mapping: Dolby Vision profile 8 and 5 strings mapped as ATV-Bilibili does
  (`hvc1` base codec plus `SUPPLEMENTAL-CODECS` for profile 8); HDR10 and HLG ranges.
- `hev1` fix: AVPlayer only accepts `hvc1` in HLS. If the init segment's sample entry is
  `hev1` and its `hvcC` box carries the VPS, SPS and PPS, the server rewrites the fourcc
  to `hvc1` (same length, bytes otherwise untouched). If it does not, that representation is
  marked unplayable and the codec fallback in section 10 applies.

**Ripper (the BTR engine)**

Section 8 describes it. Interface in short:
- `Ripper.session(for: PlaybackSource)` gives a session per playback with the representation URLs,
  their backup URLs and the node mode (overseas or mainland).
- `session.read(track:, range:, deadline:) -> AsyncThrowingStream<Data>` streams bytes in order.
- `session.playheadDidChange(seconds:)` lets the engine know how urgent each segment is.
- `session.stats()` feeds the overlay and the logs.
- Network access goes through a `Transport` protocol. The real one wraps `URLSession`; tests
  use a simulated CDN.

**DevLog**: section 9.

### 6.3 iOS app

- SwiftUI with `@Observable` models. UIKit only where it is the better tool: the player
  (`AVPlayerViewController` wrapped for SwiftUI) and the login web view.
- Screens: Home (paste button, recent list, login status), Login, Player (player, quality and
  codec pickers, BTR switch, overlay toggle), Settings (dev log server, node mode, clear data).
- `LocalServer`: Network.framework `NWListener` bound to `127.0.0.1` on a random port. Each
  playback gets a random path token, and requests without it get 404. Routes:
  `/<token>/master.m3u8`, `/<token>/v/<rep>.m3u8`, `/<token>/a/<rep>.m3u8`,
  `/<token>/v/<rep>.mp4` and `/<token>/a/<rep>.mp4` (Range requests). Media responses stream
  from `session.read` as bytes arrive, so AVPlayer starts decoding before a whole segment is in.
- `DirectPlaylistLoader`: the `AVAssetResourceLoaderDelegate` that serves playlists for direct mode
  under the `bilinative://` scheme (section 7).
- `KeychainStore` for the cookie blob.
- Info.plist: `UIBackgroundModes: audio`, `NSAppTransportSecurity.NSAllowsLocalNetworking`
  (for `127.0.0.1` and the PC log server), `NSLocalNetworkUsageDescription`,
  `NSBonjourServices: _bilinative-log._tcp`.

### 6.4 Tools

- `ripper-bench` (Swift command line, runs on Windows): given a BV id and a cookie file path,
  downloads the first N MB of the chosen representation twice, once over one connection and once
  through `Ripper`, and prints both timings and per-node stats. Cookie file values are never
  printed. If Bilibili refuses API calls from the PC (it refused non-browser requests from this
  machine in 2026-09), the bench also accepts a saved playurl JSON.
- `tools/logserver.py`: section 9.

## 7. Playback data flow

1. Link pasted, parsed, b23.tv resolved.
2. `view` gives the cid for the chosen part.
3. `playurl` gives DASH representations: per quality and codec, a base URL and backup URLs.
4. The app picks the video representation (quality and codec preference) and the best AAC audio.
5. Mode BTR: `Ripper` session created. `DashHLS` fetches init plus SIDX for both tracks through it,
   applies the `hev1` fix if needed, builds the playlists.
   Mode direct: the same playlists, but segment URIs point straight at the CDN URL with the request
   headers ATV-Bilibili uses, and the playlists are handed to AVPlayer through an
   `AVAssetResourceLoaderDelegate` custom scheme (`bilinative://`) instead of `LocalServer`. Init and
   SIDX are fetched with a single plain request. Direct mode never depends on `LocalServer`, so it
   still works when the server is the thing that failed.
6. BTR mode: `LocalServer` serves the playlists. AVPlayer gets
   `http://127.0.0.1:<port>/<token>/master.m3u8`.
7. AVPlayer requests segment byte ranges. In BTR mode `LocalServer` passes each one to
   `session.read` with a deadline computed from the segment's start time and the playhead.
8. `Ripper` splits the range into pieces, fetches them from several nodes, streams them back in
   order, and prefetches the next segments in the background.
9. A periodic observer feeds the playhead into `session.playheadDidChange` and the overlay.

## 8. The BTR engine port

Reference: BTR 2026.10.8.1 (`src/range-core.js`, `src/cdn-resolver.js`, `src/idm-downloader.js`,
`src/sidx.js`), MIT licence, credited in the app's about page and in the repo.

Carried over as BTR does it:
- Overseas and mainland node lists, host swap of signed URLs onto other nodes (keeping the signed
  path and query), the Akamai-only address synthesis, per-video bans scoped to node, address or the
  node and address pair.
- Strict response checks: HTTP 206 only, `Content-Range` must match, exact length, same total
  resource size across nodes. Anything else is a failed attempt and never reaches the player.
- Timeouts: 5.5 s to first byte, 4 s stalled stream, 15 s per attempt, up to 3 retry rounds.
- Backup copies (hedging) for slow pieces, cancelled once one copy wins; only bytes not yet
  received are re-requested once a valid prefix of at least 32 KiB is in.
- Automatic connection count: start at 16 for startup, ladder 8, 12, 16, 24, 32, 48, 64; step up on
  stalls or low buffer, step back if no gain within 10 s, back off and cool down on 412/429.
- Node speed tracking: per node first-byte time and per-connection throughput, ignoring transfers
  under 48 KiB; nodes slower than 1/12 of the fastest get no primary pieces, re-tested after 90 s.

Adapted for AVPlayer and native code:
- Unit of work is the byte range AVPlayer asks for (one SIDX segment, a few seconds of video).
  Pieces are sized from measured node speed, 64 KiB to 1 MiB.
- Deadlines: like BTR's browser mode, each segment has a playback time, so the engine always
  serves the most urgent request first.
- Hurry mode (behind a setting, off by default): segments under 10 s ahead of the playhead are
  spread across known-good nodes, with smaller pieces and earlier backup copies. This is the rule
  set KaiC measured on 2026-09-19 (startup and seeks, BTR PR 11). It is turned on only if the
  logs show the plain upstream rules leave startup or seeks slow.
- Prefetch: after serving a segment, the engine fetches the next segments ahead of AVPlayer up to
  a memory cap (64 MB for video, 8 MB for audio), so AVPlayer's next request is a cache hit.
  The cache is in memory only and dropped when playback ends or memory warnings arrive.
- Connections are reused (URLSession keeps HTTP/2 and HTTP/1.1 connections warm per host), which
  avoids the per-piece TLS handshake and slow start that made btr-ios 1.0 slower than no plugin.

## 9. Dev log streaming to the PC

Goal: every run on the phone produces a complete, readable trace on the PC, so problems are
understood from evidence instead of guess-and-retry. Claude reads the files directly.

**PC side: `tools/logserver.py`**
- Run with `uv run tools/logserver.py` (inline script metadata; only dependency `zeroconf`).
- Listens on `0.0.0.0:47321` (`--port` to change), prints the PC's LAN address and port at start,
  and advertises `_bilinative-log._tcp` over Bonjour so the phone finds it without typing.
- Accepts `POST /logs` with newline-delimited JSON, prints coloured one-line summaries, and appends
  everything to `logs/YYYY-MM-DD/<session-id>.jsonl` (gitignored).
- Windows asks once to allow Python through the firewall; allow it on private networks only.

**Phone side: `DevLog`**
- One structured event type: time, session id, level, category (`api`, `engine`, `server`,
  `player`, `ui`, `app`), message, and typed fields.
- Every app session starts with app version and build, iOS version, device model, network type.
- What gets logged:
  - `api`: endpoint, HTTP status, Bilibili `code`, duration.
  - `player`: playurl summary (qualities, codecs, hosts); AVPlayer status changes, errors,
    `AVPlayerItemAccessLog` and `AVPlayerItemErrorLog` entries, stalls and buffered ranges;
    user actions (seek, quality change, BTR switch).
  - `engine`: every piece (node, range, first-byte ms, bytes, total ms, outcome), backup copies,
    bans, concurrency changes, prefetch hits and misses.
  - `server`: each AVPlayer request (path, range, time to first byte, bytes served).
- Sinks: a rolling file on the phone (last 20 MB, always on) and the network sink (when enabled
  in Settings, Developer, Log server). The network sink batches every 500 ms, keeps up to
  10,000 events while the PC is unreachable, and resends on reconnect. Events from a session that
  crashed are sent on the next launch from the rolling file.
- Settings, Developer: discovered log servers, a manual `IP:port` field, a switch, the connection
  state, and an export button (share sheet) for when the phone is away from the PC.
- iOS asks once for Local Network permission; KaiC taps Allow.

**Privacy rules**
- Never logged: cookie values, `SESSDATA`, `bili_jct`/CSRF tokens, Authorization headers,
  passwords (the login page is Bilibili's; the app never sees the password).
- Signed CDN URLs are logged as host, path and `deadline` only. The account's `mid` is replaced
  by `mid:<hash>`.
- The network sink exists only in internal builds, behind a `DEV_TOOLS` compile flag. A public
  release build compiles it out (hard floor: shipped products never send user data anywhere).

## 10. Failure handling

| Failure | Behaviour |
|---|---|
| `LocalServer` fails to start or stops | Switch to direct mode at the current position; overlay and log say "direct (fallback)". |
| A node is slow, refuses, or sends a bad response | BTR rules from section 8: retry elsewhere, backup copy, scoped ban. |
| All nodes fail one range after 3 rounds | That playback switches to direct mode at the current position. |
| 412/429 from nodes | Concurrency backs off and cools down (section 8). |
| 412 from the API | Refresh risk-control cookies once and retry; then show the error with a retry button. |
| Signed URLs near expiry, or 403 on every node | Refetch `playurl` for the same representation, swap URLs in the session, keep node stats. |
| AVPlayer rejects a representation | Retry same quality in the next codec (AV1 or Dolby Vision, then HEVC, then AVC); remember the failure per representation type. |
| Login expired (`nav` says not logged in) | Banner with a log in button; playback continues at logged-out qualities. |
| App backgrounded or picture in picture | Audio background mode keeps the process and the server alive while playing. |
| Memory warning | Drop the prefetch cache; keep playing. |

## 11. Security and privacy

- Cookies live only in the Keychain on the phone and are only sent to bilibili.com hosts.
- `LocalServer` binds to `127.0.0.1` only and needs the per-playback random token.
- No analytics, no telemetry. The dev log sink is compiled out of public builds (section 9).
- Nothing secret is committed: signing material lives in the GitHub `testflight` environment per
  the ios-testflight skill; `logs/` and any cookie files used with `ripper-bench` are gitignored.

## 12. Testing

**On the PC (`swift test` in `Packages/BiliCore`)**
- BiliAPI: parsing of saved real responses (`nav`, `view`, `playurl` with HEVC, AV1, AVC and Dolby
  Vision entries), link parser cases, WBI signature against known input and output.
- DashHLS: SIDX parsing on real index bytes, playlist output against expected text, codec mapping,
  `hev1` rewrite on a real init segment (and refusal when parameter sets are missing).
- Ripper: a simulated CDN with nodes that are fast, slow, cold (slow first byte), refusing,
  wrong-range, truncating, stalling mid-body and rate-limiting. Assertions: bytes delivered equal the
  source exactly, urgent requests finish first, banned nodes stop getting work, concurrency backs off
  on 429, prefetch stays under its cap, fallback signal fires when every node fails. BTR's own
  `dev/shared-core-test.js` scenarios are the checklist.
- DevLog: redaction rules (no cookie or token values in any serialized event).

**On GitHub Actions (every push)**
- `swift test` for BiliCore on macOS too.
- App build with Xcode 26.6 on the `macos-26` runner image.
- Simulator test: a short HEVC plus AAC fMP4 test video with SIDX (generated with ffmpeg in the
  job) served by a local fake CDN; the app's player stack plays it through `LocalServer` for 10 s,
  seeks, plays again; a second run kills `LocalServer` mid-play and expects direct fallback.
- Screenshots of each screen saved as a build artifact.
- TestFlight upload on `main`.

**On the phone (KaiC, checklist delivered with the build)**
1. Log in; status shows the account and 大会员.
2. Start `tools/logserver.py` on the PC; enable the log server in Settings; see events arrive.
3. Paste a 4K HDR video link and play it.
4. For 3 cold, high-bitrate videos: play and seek 3 times each in BTR mode and in direct mode;
   note overlay numbers; time the official app on the same videos.
5. Picture in picture, lock screen controls, rotation.

## 13. Build and ship

- New private GitHub repo, set up with the ios-testflight skill: XcodeGen `project.yml`, bundle id
  `com.kaichuan.<slug>` once the name is picked, App Store Connect app record, `testflight`
  environment secrets, TestFlight internal testing.
- Runner image `macos-26` with its default Xcode 26.6 (iOS 26 SDK), deployment target iOS 26.
  Chosen over the `xcode-27` preview image for stability and wider device support. iOS 27-only
  APIs are not used; Liquid Glass is available because it arrived in iOS 26.
- Windows setup: the Swift toolchain is not installed on this PC any more and must be installed
  (latest stable, version checked at plan time). Sideloadly must keep using its Swift-safe
  launcher, because Swift's `Foundation.dll` on PATH breaks Sideloadly's login.

## 14. Risks and open questions

| Risk | Mitigation |
|---|---|
| AVPlayer rejects Bilibili's HEVC or Dolby Vision via local HLS | ATV-Bilibili ships this approach; `hev1` fix; codec fallback; first CI test exercises it. |
| AV1 in fMP4 HLS on AVPlayer is unproven | Codec picker makes it a test item; HEVC is the default. |
| BTR gives no gain with AVPlayer's request pattern | That is what milestone 1 measures; stop if so. |
| Web API risk control (412) inside an app | Safari-like headers, risk-control cookies, logs show the exact responses. |
| Account risk from a third-party client | Same risk as PiliPlus, which KaiC accepted in 2026-09. |
| Bilibili refuses API calls from the PC | `ripper-bench` accepts saved playurl JSON; phone logs are the primary data anyway. |
| FoundationNetworking on Windows behaves differently from iOS | Real transport is only used by the bench on Windows; engine logic is tested with the simulated transport. |

## 15. Rules for going public later

- Own name and icon, no Bilibili logo or wordmark; layout and colours may follow the official app.
- No code copied from ATV-Bilibili (GPL-2.0) or PiliPlus (GPL-3.0); they are references for
  endpoints and formats only. BTR (MIT) is ported with its licence text kept.
- Dev log network sink compiled out of public builds.

## References

- BTR: https://github.com/MrTangLuyao/Bilibili-thread-ripper (2026.10.8.1)
- ATV-Bilibili-demo (AVPlayer, DASH to HLS, SIDX): https://github.com/yichengchen/ATV-Bilibili-demo
- PiliPlus (endpoints, login, playurl flags): https://github.com/bggRGjQaUbCoE/PiliPlus
- lemonteaau/PiliPlus `docs/thread-ripper.md` (native port of BTR, byte-window model)
- btr-ios (official app request pattern, Loon limits): https://github.com/xirenjie0101/btr-ios
