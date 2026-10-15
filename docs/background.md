# Background

Context gathered before this repo existed (2026-09 to 2026-10-16), so later sessions do not have to
rediscover it. The spec records the decisions; this file records the evidence and history behind them.

## How the project got here

The goal is the speed of Bilibili Thread Ripper (BTR, a browser extension and userscript that downloads each
video chunk from several CDN nodes at once) on an iPhone, overseas, where cold and high-bitrate videos
buffer badly.

Options tried or rejected, in order:

1. **Sideloading PiliPlus** (open-source Flutter client) with BTR built in: `lemonteaau/PiliPlus` (daily
   upstream sync, unsigned IPA) and `nishuodedui1145-del/PiliPlus`. Fast, but rejected by KaiC after using
   it: Flutter feels like the web version, much worse than the official app (rotation, layout, overall feel).
2. **Re-skinning PiliPlus in Flutter**: rejected for the same reason; the problem is the feel, not only the look.
3. **Speeding up the official app**: only possible at the network level (a VPN-style proxy app that
   intercepts the CDN traffic with a user-installed root certificate). `xirenjie0101/btr-ios` does this as a
   Loon script. Its real-device notes are the best evidence about the official app (see below). Not chosen:
   needs a MITM certificate, takes the phone's only VPN slot, and the gain was unproven.
4. **Native Swift client** (this repo): chosen. Real iOS feel, Apple's player, BTR engine underneath.

## Prior art and what it is good for

| Project | Licence | Use it for | Do not |
|---|---|---|---|
| [ATV-Bilibili-demo](https://github.com/yichengchen/ATV-Bilibili-demo) (Swift, Apple TV, ~3k stars) | GPL-2.0 | Proof that AVPlayer plays Bilibili DASH as HLS: `BilibiliVideoResourceLoaderDelegate.swift` builds playlists with `EXT-X-MAP` + `EXT-X-BYTERANGE` from the SIDX, maps Dolby Vision codec strings, serves playlists through an `AVAssetResourceLoaderDelegate` custom scheme | copy code |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) (Flutter) | GPL-3.0 | API endpoints, playurl flags, login flows, field names | copy code |
| [lemonteaau/PiliPlus](https://github.com/lemonteaau/PiliPlus) `docs/thread-ripper.md` | GPL-3.0 | Notes from porting BTR to a native player behind a localhost Range proxy: player disconnects must cancel downloads at once, a new request on the same track supersedes the old one, mpv buffers only ~16 s | copy code |
| [btr-ios](https://github.com/xirenjie0101/btr-ios) (Loon plugin) | see repo | How the official app fetches video (below) | |
| [BTR](https://github.com/MrTangLuyao/Bilibili-thread-ripper) | MIT | The engine this repo ports (tag `2026.10.8.1`, `src/range-core.js`, `cdn-resolver.js`, `idm-downloader.js`, `sidx.js`) | forget the licence notice |

**What btr-ios learned on a real iPhone (2026-09):** the official app's player (ijkplayer, User-Agent
`Bilibili Freedoooooom/MarkII`) asks for about 1 MB at a time (`Range: bytes=a-b`) and waits for each piece
before asking for the next; it also opens `bytes=a-` ranges. Intercepting the CDN with MITM works (no
certificate pinning seen). Splitting each 1 MB request over several nodes was slower than doing nothing,
because every split opened a fresh connection that never left TCP slow start. Gains need fetching ahead over
warm connections. AVPlayer asks for whole SIDX segments (a few seconds each), which suits BTR better.

## What Bilibili's CDN nodes actually do

Measured from KaiC's PC (overseas, 2026-09-19) with BTR's debug report, 1080P+ HEVC, overseas mode. Trust
these over any simulation.

- **Hot vs cold content.** A node that served a range recently ("hot") answers fast; a range right after a
  seek is "cold" and every node is slow there, each differently:
  - `upos-hz-mirrorakam.akamaized.net`: hot first byte 20-200 ms, 5-9 MB/s per connection (fastest node);
    cold first byte 0.9-1.6 s, then the following ranges are hot.
  - `upos-sz-mirroraliov`: hot first byte 25-50 ms, about 4 MB/s; cold: first byte ~40 ms, then a trickle of
    45-100 KB/s per request.
  - `upos-sz-mirrorcosov`: hot first byte 180-370 ms, about 3 MB/s; cold ~200 ms first byte and ~0.7 s per
    70 KiB, the most dependable on cold ranges.
  - `cn-hk-eq-01-01/03`: 600-1200 ms first byte, 20-200 KB/s; close to useless from there.
- **Protocols.** mirrorcosov, mirroraliov, the HK nodes and the mainland mirrors negotiate HTTP/2 (all
  "threads" to one host share one TCP connection, so real parallelism is the number of distinct nodes).
  akamaized.net is HTTP/1.1 only (six connections per host in browsers).
- **Piece size.** 64 KiB pieces never leave TCP slow start (aliov: 394 KB/s with 64 KiB pieces vs 4158 KB/s
  with ~400 KiB pieces). Large pieces win on hot content and lose badly on cold content (one trickling 400 KiB
  piece took 3.9 s).
- **Akamai-only accounts.** Some accounts get only akamaized.net addresses; the primary `os=cosovbv` address
  was refused (HTTP 403) on every node while the `os=akam` backup worked everywhere, mirrors included. This is
  why BTR (and this port) uses Akamai addresses as host-swap donors when nothing else exists, and why bans are
  scoped to node, address or node+address pair.
- **Seek cost.** In the browser with BTR, seek to playing took 1.5-3.1 s; rebuilding the player was only
  ~0.2 s of that, the rest was the first segment's download. The floor is the CDN's cold-range latency.
- **Bugs found from real data in BTR's scheduler work** (worth avoiding in the port): a startup buffer target
  that re-measured throughput while waiting and kept inflating; duplicate bytes from cancelled copies never
  counted; a slow node keeping its "hot" speed because its pieces were always finished by faster copies
  first (survivor bias; fixed by sampling cancelled transfers, which this port does).

## Hurry mode (deferred)

KaiC's own BTR scheduler work (BTR PR 11, not merged upstream) added rules that helped startup and seeks in
the browser: pick the node by expected finish time; when little is buffered, spread pieces (unknown nodes
cost twice the best per piece, no node takes more than half when three or more are known); a 250-600 ms
hedge budget; a node whose request lost a race before sending anything gets a higher first-byte estimate; a
crawling node's speed is lowered; piece size `clamp(fastest bps x 0.15 s, 64 KiB, 512 KiB)`. The JS lives in
`D:\Repos\Apps\Bilibili-thread-ripper` on branch `perf/piece-scheduler` (commit `a7e5f38`) and, rebased on
BTR 0.9.1.5, on `local/0.9.1.5-with-scheduler` (`24631bc`). Port it only if the milestone 1 phone logs show
startup or seeks are slow.

## Known environment limits

- Bilibili's web API refused non-browser requests from KaiC's PC in 2026-09. The app sends Safari-like
  headers and the fingerprint cookies (`buvid3`/`buvid4`); the PC speed test can fall back to a saved
  playurl response.
- Signed media URLs carry a `deadline` query parameter (Unix seconds) and stop working after it; the app
  refreshes them five minutes before.
