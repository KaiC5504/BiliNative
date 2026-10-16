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
  scoped to node, address or node+address pair. On 2026-10-16 (KaiC's account, PC) only Akamai refused
  `os=cosovbv`; the mirrors served it.
- **Damaged edge copies.** On 2026-10-16 Akamai's copy of KaiC's q80 HEVC file lacked bytes 109972 through
  1048575 (the end of the first MiB): a range crossing 109972 got a 206 and was cut off there, a range starting
  inside the gap got no response at all (connection closed before headers), and every range from 1 MiB on was
  whole and fast. The mirrors served the whole file.
- **Seek cost.** In the browser with BTR, seek to playing took 1.5-3.1 s; rebuilding the player was only
  ~0.2 s of that, the rest was the first segment's download. The floor is the CDN's cold-range latency.
- **Bugs found from real data in BTR's scheduler work** (worth avoiding in the port): a startup buffer target
  that re-measured throughput while waiting and kept inflating; duplicate bytes from cancelled copies never
  counted; a slow node keeping its "hot" speed because its pieces were always finished by faster copies
  first (survivor bias; fixed by sampling cancelled transfers, which this port does).

## Hurry mode

KaiC's own BTR scheduler work (BTR PR 11, not merged upstream) added rules that helped startup and seeks in
the browser: pick the node by expected finish time; when little is buffered, spread pieces (unknown nodes
cost twice the best per piece, no node takes more than half when three or more are known); a 250-600 ms
hedge budget; a node whose request lost a race before sending anything gets a higher first-byte estimate; a
crawling node's speed is lowered; piece size `clamp(fastest bps x 0.15 s, 64 KiB, 512 KiB)`. The JS lives in
`D:\Repos\Apps\Bilibili-thread-ripper` on branch `perf/piece-scheduler` (commit `a7e5f38`) and, rebased on
BTR 0.9.1.5, on `local/0.9.1.5-with-scheduler` (`24631bc`).

Built on 2026-10-16, after the milestone 1 phone logs showed a cold 4K start of 8.7 s and stalls right after
a jump. It lives in `Sources/Ripper/NodeStats.swift` (per-node first byte, speed and load),
`HurryPlacement.swift` (which node gets which piece), `PieceDownloader.swift` (the hedge budgets and the
third copy) and `RangeDownloader.swift` (piece size and when a range counts as in a hurry). The rules are
listed under "Deviations from BTR". `RipperConfig.hurry` switches all of it off, which is how `ripper-bench
--seeks N --no-hurry` gets its baseline. Whether it helps on the phone is not yet measured.

## Deviations from BTR

- Blip strikes heal: a successful transfer clears a node's empty-reply strikes and lifts a node ban they
  caused, so a local network blip doesn't ban the fastest nodes for the rest of the video (2026-10-16, after
  the Task 18 review).
- Requests that lose their connection before any byte (no status, not a timeout) at one moment are one strike,
  whatever their nodes: a later loss within 250 ms of the first one of the moment adds none (`BanList`,
  `lossMomentAt`). The window does not stretch, and BTR's retry rounds pause at least 500 ms, so a node that
  drops every request is still banned by its second moment. On the phone (2026-10-17, t+139.08 s) two Akamai
  requests lost their connection (NSURLError -1005) 2 ms apart and banned the fastest node for the rest of the
  video. Two earlier -1005s in mid-body (t+105.8, t+134.6) had been taken as damaged copies and used up
  Akamai's two damaged blocks for that file, which is why these were strikes at all. Path updates arrived at
  t+106.5 and t+141.5 with Wi-Fi still up and the same interfaces and gateways; `PlaybackController` passes a
  path change to `RipperSession.networkChanged` only when that signature changes, so none of them reset the
  bans.
- A refusal (HTTP 4xx) of an address other nodes serve, by a node that has not delivered yet, drops only that
  node and address pair, however many such addresses it refuses (both tracks and every new signature are
  further addresses). BTR blames the node (`cdn-resolver.js` line 133 at 2026.10.8.1), and a banned node never
  gets to prove its other address, so the ban never lifts: overseas, cold Akamai lost every early race on
  `os=akam`, was banned for refusing `os=cosovbv`, and the fastest node went unused for the whole video
  (2026-10-16, ripper-bench q80 runs).
- Damaged copies: when a node that is up (it has sent bytes) breaks off without a status and not by a timeout
  (cut short, or no response at all), the position is recorded for that node and file, from that byte to the
  end of its MiB. Pieces and backup copies touching it go to other nodes while any other allowed node is left;
  the header (init and index) fetch does not check it. The rest resumes elsewhere as before. Such a failure is
  no strike and no backoff for up to two damaged blocks per node and file; damage in a third block is struck as
  before and not recorded. A network change forgets all damage. In BTR the empty replies inside Akamai's gap
  struck the node and banned it after two (2026-10-16, q80 runs).
- Hurry mode, the BTR PR 11 rules as ported (2026-10-16). A range is in a hurry when it is a startup or seek
  range, or its segment starts less than `hurryAheadSeconds` (10) of playback ahead of the playhead. The check
  is re-read each time it is asked, so a prefetch the playhead catches up with turns into a hurry. In a hurry:
  - Pieces are small: the 64 KiB floor, not the adaptive size, so a range splits over every connection. The
    64 KiB probe head runs only when no node is known yet.
  - Each piece's first node is picked by expected finish time (`NodeStats.expectedMs`: first byte plus piece
    size over the node's speed shared with what it already carries). A node not measured yet costs twice the
    best known node, times its pieces in flight plus one. With three or more hosts a node that carries at least
    two pieces and more than half of all in flight gets a large penalty, so no node takes more than half. A
    single host (an Akamai-only account) takes every piece. A full node goes last, and an address that has not
    delivered yet loses ties.
  - Hedge budgets: with no first byte yet, a second copy starts after `clamp(first byte x 2, 250, 600)` ms
    (250 ms if the node's first byte is unknown). If bytes stop arriving, a copy starts after a 1 s gap. A slow
    transfer gets a copy once `elapsed >= max(400, expected x 2)` ms while under 75% of the piece has arrived;
    for a node not measured yet `expected` is the best known candidate's for that piece, so a node that answers
    and then trickles is not left alone for twice the hedge delay (2026-10-17). With no node known it is the
    hedge delay, as before. Outside a hurry the usual 900 ms hedge delay applies.
  - Every copy after the first goes to the candidate expected to finish first, at the costs above (unknown,
    full, not yet delivered) but without the half share, since a copy is one request (BTR PR 11 `pick`). The
    first copy stays on its placed node. Outside a hurry later copies keep the speed order. Before this a copy
    went by speed alone: on the phone's start (2026-10-17, t+99 s) copies went to cosov, 661-673 ms to the first
    byte, while Akamai answered in 15-24 ms.
  - At most three copies of a piece, and copy k starts only when copy k-1 is late. A range that is not in a
    hurry never starts a third copy.
  - `NodeStats` blends new samples 0.7 old, 0.3 new. Bodies under 32 KiB say nothing about speed. A request
    that was cancelled after losing a race before any byte raises the node's first-byte estimate. A cancelled
    transfer counts as a crawl only after 300 ms and only if it was slower than the node's current speed. A
    node is assumed to carry at least 4 connections at full speed. A network change clears it.
- Busy-node rule: a request that gets no first byte in time from a node that is sending other pieces is no
  strike and no `slow()` signal. It waited behind those transfers (URLSession's 8-per-host limit for Akamai's
  HTTP/1.1, or the node's own queue). It still counts as a failed request, and the `attempt failed` log line
  carries `busy: true`. The node's connection limit drops to what it was receiving, so new pieces stop piling
  onto it and the range finishes from other nodes. Before this rule, one cold jump gave Akamai and cosov two
  first-byte timeouts each while both were busy, and both were banned for the rest of the video (BV1bmpt6WEom
  at 1:49:47, 2026-10-16).
- Full nodes are skipped outside a hurry too. Akamai answers only HTTP/1.1 and URLSession opens 8 connections
  per host, so Akamai counts as full at 8 requests in flight from the start (`RangeTransport.connectionsPerHost`,
  `NodeStats`). `PrimaryAssigner` lets a full node sit its turns out while another node has room, and every copy
  of a piece, the first one included, takes its node only once it holds a connection permit: the first candidate
  with room, or the first one left when every node is full (`CopyTargets`). Before this, on the phone
  (logs/2026-10-17, t+122-139 s), threads went up to 48-64 and Akamai, measured fastest, carried 48-61 requests
  while aliov and cosov carried 0-8 and answered in about 100 ms. 38 requests ran out their first-byte timeout
  inside URLSession (`busy: true`) and playback stalled twice; pieces placed on Akamai earlier also started all
  at once when the threads went from 48 to 64. The first-byte clock still starts when the request is handed to
  URLSession, which reports no moment of sending; now a request waits there only when every node is full.
- A prefetch the player adopted survives the player's cancel. Before this, the player's request was the
  prefetch's only owner, so when AVPlayer gave up after 5 s of silence and cancelled, the 7 finished pieces
  were thrown away and fetched again (BV1jt421t7XH, 2026-10-16). `close()` and a seek (`dropPrefetch`) still cancel it.

## Known environment limits

- Bilibili's web API refused non-browser requests from KaiC's PC in 2026-09. The app sends Safari-like
  headers and the fingerprint cookies (`buvid3`/`buvid4`); the PC speed test can fall back to a saved
  playurl response.
- Signed media URLs carry a `deadline` query parameter (Unix seconds) and stop working after it; the app
  refreshes them five minutes before.
