# Milestone 1 results

KaiC's iPhone 17 Pro Max (iOS 27.0.1), overseas, home Wi-Fi, TestFlight builds 1 and 2, 2026-10-16. Numbers come
from the app's own logs (`logs/2026-10-16/*.jsonl`, not committed). KaiC compared against the official app by
eye: the videos he picked lag there.

The checklist's strict protocol (three cold videos, alternating mode order, fixed seek positions) was not
followed to the letter. KaiC played a mix of 1080P and 4K videos and flipped 加速 on and off on four of them.
The difference was large enough that he called it without the full table.

## Verdict: go

Spec section 5 asks that BTR beat direct on first frame and seek-to-resume, with no more stalls, and feel at
least as good as the official app. On every video tried in both modes, BTR started faster and stalled far
less. KaiC: lag in direct mode is "significant" / "extreme long more than 10s"; with BTR "nearly no lag at all
and start almost instantly", "way better" than the official app.

## Per video

First frame is from tapping play to the first rendered frame. Stalls count only stalls during playback. The
wait right after a drag was not split out in build 1, so build 1 rows below were read by hand.

| Video | Stream | BTR | 直连 |
|---|---|---|---|
| BV1bmpt6WEom (2.6 h) | 1080P+ HEVC 2.0 Mbps | first frame 0.75-0.97 s (3 opens); one stall after a jump to 1:49:47, where Akamai and cosov sent nothing for 5.5 s | not tried |
| BV1bMdEY1E2r | 1080P60 HEVC 1.5 Mbps (direct: H.264 2.3 Mbps) | first frame 0.57-1.04 s (5 opens); no stall while playing untouched; seeks resumed 0.02-0.5 s after letting go (worst 1.4 s) | first frame 1.35 s; stuck 18.6 s at 0:05, stalled again at 0:20 |
| BV1jt421t7XH | 4K HEVC 19 Mbps (direct: AV1 19.3 Mbps) | first frame **8.7 s cold**, then 1.9 s and 0.84 s on reopen; 3 short stalls | first open never started (gave up after ~65 s); second 9.7 s; stalls of 14 s and 15+ s |
| BV1jt421t7XH | 杜比视界 (126) | first frame 4.4 s, played | not tried |
| BV198S7B8E6C | 4K HEVC 10 Mbps (direct: AV1 15 Mbps) | first frame 1.45 s; one stall after a reload | first frame 1.82 s; 3 stalls, the last stuck 18+ s until KaiC switched to BTR |
| BV1obha6hEjS | 4K AV1 5.9 Mbps | first frame 1.98 s; 2 short stalls after jumps | not tried |
| BV1m9pj6SEPR | 4K HEVC 5.5 Mbps | first frame 1.41 s; 2 short stalls after jumps | not tried |

Direct mode skips HEVC streams labelled `hev1` (AVPlayer needs the init rewrite only BTR does), so it played
H.264 or AV1 instead. Its stream was bigger on two of the three videos (2.3 vs 1.5 Mbps, 15 vs 10 Mbps) and
about equal on the third. That is not a perfectly fair comparison, but the gap in stalls (seconds vs none or
under 3 s) is far larger than the bitrate difference explains.

## Where BTR still struggles

- **Cold 4K start.** BV1jt421t7XH's first open took 8.7 s. The first segment the player needs is about 20 MB,
  and one piece sat on Akamai, which sent nothing for the whole 5.5 s first-byte timeout before the engine moved
  it. Reopening the same video, with the CDN warm, took 0.84-1.9 s.
- **The first seconds after a jump into an unloaded part of a 4K video.** Cold ranges answer after a 1.2-2.5 s
  first byte on every node (`firstByteMs` in the piece logs). AVPlayer resumes with only a few seconds buffered,
  and the next segment is not there yet.
- Both are the case the deferred hurry mode targets (`docs/background.md`, "Hurry mode"): when little is
  buffered, hedge a silent piece after 250-600 ms instead of waiting for the timeout, and spread pieces by
  expected finish time.
- **Node bans after one cold range.** On BV1bmpt6WEom a single cold jump banned both of the fastest nodes for
  the rest of the video: each had two first-byte timeouts from the same moment.

## Bugs found on the phone (all fixed in build 2)

- Full screen crashed (`UIViewControllerHierarchyInconsistency`): the stats overlay's hosting controller was a
  child of AVPlayerViewController, and AVKit moves the overlay into its own full-screen controller.
  Regression test: `ios/Tests/AppTests/FullScreenTests.swift`.
- After about 20 minutes in the background, the first BTR video fell back to direct. iOS had taken the local
  server's socket while the listener still reported ready. BTR now checks that the server answers before it
  starts.
- 卡顿 counted the wait right after a drag as a stall. Logged stall timestamps are 0.25 s after the stall
  began. Some drags still land 0.35-0.65 s after the wait starts, because AVKit reports the jump only when the
  seek lands, so a few drag waits are still counted in build 2.

## Not checked on the phone

- Wi-Fi to cellular mid-video.
- Lock screen controls.
- PiP.
- The background fix itself: no build 2 background lasted long enough for iOS to take the socket.

## Hurry mode

Built 2026-10-16 (plan `docs/superpowers/plans/2026-10-16-hurry-mode.md`). Phone retest pending.

PC bench, overseas, the saved playurl of one video (`ripper-bench --seeks 8`, seed 17, 8 jumps of 4 MiB each).
Whichever run reads an offset first meets a cold CDN edge and is slow, so runs on fresh offsets are compared with
each other, and runs on already-read offsets with each other. The cold rows are different streams of the same
video, not a perfect A/B.

| Run | First MiB (median) | Whole 4 MiB (median) |
|---|---|---|
| Cold, hurry on: 4K / 8K / 1080P | 1.68 / 1.59 / 1.59 s | 2.18 / 2.17 / 2.46 s |
| Cold, hurry off: 1080P60 | 4.39 s | 6.99 s |
| Warm 4K, hurry on | 0.35 s | 0.41 s |
| Warm 4K, hurry off | 0.17 s | 1.46 s |
