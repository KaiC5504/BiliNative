# BiliNative, milestone 2: player and video page (design)

Date: 2026-10-17. Status: draft for KaiC's review.

## 1. Why this exists

Milestone 1 proved the engine: BTR starts faster and stalls far less than direct playback on KaiC's phone
(`docs/m1-results.md`), and hurry mode fixed slow jumps. The app around it is still a test bench: a paste box, a
recent list, AVKit's own player and a settings list under it. Milestone 2 turns that into the official app's
video experience, so KaiC can use BiliFast instead of the official app for watching.

Success is KaiC choosing BiliFast over the official app for everyday watching: same layout, gestures and
actions, but faster playback.

## 2. Decisions already made

| Decision | Choice | Decided by |
|---|---|---|
| Scope | Player chrome, gestures, danmaku, video page, actions, comments, related, 合集/分P, history, plus a 推荐-only home and a 历史记录 page pulled forward from milestones 3 and 4 | KaiC |
| Shipping | One spec and one plan, two TestFlight builds: build A the player, build B the page | KaiC |
| Look | 100% the official app (`docs/official-app-reference.md`); no liquid glass | KaiC |
| Full screen | Turning the phone enters and leaves landscape full screen; the button and a rotation lock work too; vertical videos go full screen in portrait | KaiC |
| Gestures | Double tap play/pause, hold for 2×, horizontal swipe seeks, vertical swipe brightness (left) and volume (right). All work in full screen; the small portrait player has all but brightness/volume | KaiC |
| Leaving the app | Auto picture in picture only; no background audio | KaiC |
| Dev controls | BTR switch and stats overlay move into the player's ⋮ panel | KaiC |
| Danmaku | Show, tune (the full 弹幕设置 panel), block words synced with the Bilibili account, send with style | KaiC |
| Comments | Read (hot/new, threads), write and reply with text and emotes, like | KaiC |
| Actions | 点赞, 不喜欢, 投币, 收藏, 分享, 长按三连, 关注 | KaiC |
| 不喜欢 | Needs an app token: KaiC confirms once on Bilibili's TV-login page inside the app | KaiC |
| App key and secret | Bilibili's public TV client pair comes from a GitHub secret at build time, never committed | KaiC |
| History | Report progress to Bilibili and resume where the account left off | KaiC |
| End of video | Next 分P or 合集 episode; a single video stops on the end screen | KaiC |
| Extras | Chapters yes; subtitles, seek thumbnails, tap-a-danmaku and 当前弹幕列表 no | KaiC |
| ⋮ panel | 定时关闭, 自动连播, 循环播放, 稍后再看, 画面尺寸, 镜像翻转. Not 听视频, 后台听视频, 投屏, 色觉辅助, 播放反馈, 编辑播放器 | KaiC |
| Coin dialog art | The official 22娘/33娘 art, loaded at run time from Bilibili's own servers, never committed (falls back to our own drawing) | Claude, after KaiC asked for the official art |
| Icons | Drawn by us as vectors to match the screenshots, or SF Symbols where one matches. Nothing copied from PiliPlus (GPL) or Bilibili's app | Claude, KaiC asked to be told if PiliPlus's icons could not be used |
| 充电 | Left out everywhere: it spends real money | Claude |
| API source | Bilibili's web API with the existing cookie login, signed with WBI and the `bili_jct` CSRF token. The app API only for 不喜欢 | Claude |

## 3. Scope

### 3.1 Build A: the player

- Our own player view over `AVPlayerLayer`, replacing `AVPlayerViewController`.
- The small portrait player, landscape full screen, and 竖屏 full screen, each with the official chrome.
- Gestures, the 清晰度 and 倍速 pickers, the ⋮ panel, chapters on the bar, the end screen.
- Picture in picture through `AVPictureInPictureController`.
- Danmaku: segments, rendering, the settings panel, cloud block words, sending with style.
- History: heartbeat reporting and resume.
- The rest of the page stays as it is in build A, except that the M1 settings list under the player is replaced
  by a temporary title line and the 分P list, so the page has no dead controls.
- Controls that belong to build B are hidden in build A, not shown disabled: the action buttons and "+ 关注" in the
  full-screen top bars, 09's action column and 关注, and 27's action buttons. "N人正在看" and the related videos on
  the end screens (26, 27) are in build A, since they are one read-only call each. (Claude's call.)

### 3.2 Build B: the page and the entry points

- The video page under the player: 简介 and 评论 tabs, uploader row, title and stats, the action row with all
  actions, 合集 and 分P, tags, related videos.
- Comments: list, sort, reply threads, composer with emotes, like and 踩, delete own.
- The app token for 不喜欢.
- A 首页 with the 推荐 feed, and a 历史记录 page.

### 3.3 Out of scope

Search, the bottom tab bar, other home tabs, 关注/动态, 我的, 我的收藏 page, PGC (anime, films), live,
downloads, subtitles, seek thumbnails, tapping a danmaku, the danmaku list, 人像防挡 (smart mask), command and BAS
danmaku, ads, 投屏, 听视频, background audio, 充电, posting pictures in comments, @-mention picking, iPad layout,
English UI.

## 4. Screens and behaviour

Every screen copies the matching screenshot in `local/official-app-reference/` (read `docs/official-app-reference.md`
and the image before building it). The numbers below are the screenshot numbers.

### 4.1 Opening a video

A video opens on a video page pushed onto the navigation stack. Opening a related video, a 合集 episode from
another bvid, a feed card or a history row pushes a new page; back returns to the previous one, which resumes
paused where it was. Only the top page owns a running player; a page that is covered stops its player and its
engine session (the M1 rule that a covered page must not keep its `RipperSession` registered still holds).

Autoplay is different: when the next item (a 合集 episode with another bvid, or 列表循环 wrapping) belongs to
another bvid, the current page switches to it in place and reloads its info, relation, comments, danmaku, related
list and online count, so the stack never grows by itself. Back still leaves the page. (Claude's call; the
official app does the same.)

A page needs a bvid; a cid and a start position are optional. Without a cid it plays the first part, or the part
`last_play_cid` names. Without a start position it resumes at the playurl response's `last_play_time`
(milliseconds) when that belongs to the part being played and is more than 5 s from the end; otherwise it starts
at 0.

### 4.2 The small portrait player (15, 03)

- 16:9 box under a black status bar, the video fitted inside (vertical videos too).
- Tap shows the controls, which hide 3 s after the last touch. Controls: back at the top left, ⋮ at the top
  right; bottom row play/pause, progress bar with the TV-face thumb (our drawing), "00:01/03:15", the 竖屏 button
  (corner brackets with a 竖屏 pill; every video has it, 15 and 18), and the full-screen button.
- Chapter marks sit on the bar where the video has chapters (`x/player/wbi/v2` `view_points` with `type == 2`);
  the current chapter's title shows above the bar while dragging.
- A thin progress line stays at the bottom edge while the controls are hidden.
- Danmaku shows over the video in the small player too.
- Loading shows a spinner; a failure shows the message and a 重试 button in the player box.
- When paused, scrolling the page shrinks the player, then collapses it into a short dark bar with back,
  "▶ 继续播放" and ⋮ (11, 12). Tapping 继续播放 expands it and plays. While playing the player stays full size.

### 4.3 Landscape full screen (04)

- Entered by turning the phone or the full-screen button; for a vertical video the full-screen button opens 竖屏
  full screen (4.4) instead. Left by turning back, the back chevron, or the button.
- Top bar: back, the title (the part title for multi-part videos), "N人正在看", the uploader avatar with
  "+ 关注"; at the right 点赞 (count), 评论 (count), 收藏 (count), 投币, 分享, ⋮. 充电 is left out. 评论 leaves full
  screen and switches to the 评论 tab.
- Right edge: the screenshot button (saves the current frame to Photos) and the rotation lock.
- Bottom: time above the bar; play/pause, danmaku on/off, danmaku settings, the danmaku field
  "发个友善的弹幕见证当下", 倍速, quality (shows the current quality's short name, such as 4K), and 选集 when the
  video has parts or a 合集.
- Pickers and panels slide in from the right on black (05, 06, 07-08, 20-21, 24) and dismiss on a tap outside.
- The rotation lock keeps the current orientation until unlocked, and survives until the page closes.
- Turning the phone with a vertical video playing does nothing; vertical videos reach landscape only through the
  full-screen button in 竖屏 mode (09, bottom right). (Claude's call.)
- Actions opened from full screen stay in full screen (Claude's call): in landscape the coin dialog is the same
  centred dialog laid out for the wider screen, 收藏 opens as a right-side panel like the other panels, 分享 uses the
  share sheet over the player, and the unfollow confirm is an alert. In 竖屏 full screen they open as in portrait.
  Each of these presentations over the rotated player gets its own simulator transition test (section 8).

### 4.4 竖屏 full screen (09)

The 竖屏 button (any video) goes to the 09 layout, staying in portrait: black page, the video centred and as wide
as the screen (a vertical video fills the height instead), back and "N人正在看" at the
top with ⋮; the action column on the right (点赞, 评论, 投币, 收藏, 分享 with counts); the uploader with 关注, the
title and "N播放" at the bottom left; a progress bar; the "发弹幕" field with the 弹 toggle, the 详情页 button
(back to the page) and the landscape full-screen button. The search suggestion row is left out (no search yet).
Gestures work as in landscape full screen.

### 4.5 Gestures

| Gesture | Where | Effect |
|---|---|---|
| Single tap | anywhere on the video | show/hide controls |
| Double tap | anywhere | play/pause |
| Hold | anywhere, while playing | 2× while held, the "⏩ 倍速中" pill at the top centre (25); release restores the speed |
| Horizontal drag | anywhere | seek; 90 s per full player width; a centred "01:23 / 03:15" label while dragging; committed on release |
| Vertical drag, left half | full screen only | screen brightness; full height = 100% |
| Vertical drag, right half | full screen only | system volume; full height = 100% |

Direction locks once the finger has moved 10 pt, to whichever axis moved more. In the small portrait player a
vertical drag is left to the page so it scrolls. Touches within 25 pt of the screen edges are ignored in full
screen so the system's edge gestures still work. Volume uses a hidden `MPVolumeView` slider (the only public way
to set the system volume), with the system volume HUD suppressed and our own brightness/volume indicator shown
instead.

### 4.6 Pickers

- 清晰度 (05): 自动, then every quality the playurl response offers, best first, with the 大会员 pill on qualities
  that need it (qn 112 and up). The playing one is pink. Qualities the account cannot play are shown but tapping
  one says "开通大会员后可观看". 自动 plays the best quality the account allows and never switches mid-video.
  高级设置 > opens the codec choice (HEVC, AV1, AVC), moved here from the M1 list.
- 倍速 (06): 3.0X, 2.0X, 1.5X, 1.25X, 1.0X, 0.75X, 0.5X; the current one pink. The speed stays for the page's
  life, including the next part.

### 4.7 The ⋮ panel (20-21)

Landscape: a right-side panel; portrait: the same content in a bottom sheet.

- Square buttons: 稍后再看 (adds to watch later; "已添加至稍后再看") and 小窗播放 (starts picture in picture).
- 定时关闭: 不开启 / 15:00 / 30:00 / 60:00 / 自定义 (a minutes picker). When the timer runs out, playback pauses.
- 自动连播 toggle (default on): at the end, go to the next part or 合集 episode. 循环播放: 单集循环 / 列表循环 /
  不循环 (default 不循环). 单集循环 overrides 自动连播.
- 镜像翻转 toggle. 画面尺寸 >: 适应 (default), 填充, 拉伸, 16:9, 4:3.
- A last card for testing: BTR 加速 (the M1 switch, reloads at the current position) and 显示统计 (the M1 stats
  overlay). They are not in the official app; they stay because KaiC compares modes.
- Settings in this panel are saved in `AppSettings` and apply to every video, except 定时关闭 and 镜像翻转, which
  last for the page.

### 4.8 End of a video (26, 27)

When a video ends and nothing plays next: portrait shows "推荐视频" with the first related video, "立即播放", and
重播 and 分享 (26); landscape shows the uploader with 关注 (no 充电), 重播 | 点赞 投币 收藏 分享, and a row of
related videos (27). Autoplay order: 单集循环 replays; otherwise, with 自动连播 on, the next part, then the next
合集 episode; with 列表循环, wrap to the first. A 5-second "即将播放 …" countdown is not shown; it switches at once
like the official app.

### 4.9 Danmaku

**Fetching.** Danmaku arrive in 6-minute segments from `GET /x/v2/dm/web/seg.so?type=1&oid=<cid>&segment_index=<n>`
(1-based; protobuf). The segment holding the playhead loads at start and after every seek; the next one loads
when the playhead is within 30 s of the boundary. Each segment loads once per page. A failed segment is retried
on the next boundary or seek. `state == 1` in the reply means the uploader closed danmaku: nothing shows and the
send field says "UP主已关闭弹幕".

**Decoding.** A small protobuf reader in BiliCore (no third-party package) decodes `DmSegMobileReply` (1 elems)
and `DanmakuElem` (1 id, 2 progress ms, 3 mode, 4 fontsize, 5 color, 6 midHash, 7 content, 8 ctime, 9 weight,
11 pool, 12 idStr, 13 attr, 24 colorful), skipping unknown fields.

**Modes.** 1 scroll right to left, 4 bottom, 5 top, 6 reverse scroll. 7 (advanced JSON), 8 (code) and 9 (BAS)
are dropped.

**Layout.** Lanes are the danmaku font's line height. A scrolling danmaku takes the first lane where it will not
catch the one ahead of it before that one leaves; when none is free it is dropped (no overlap). Top and bottom
danmaku take the first free lane from their edge and stay for 4 s. The lane maths is a pure function in BiliCore,
tested there. The display area setting limits the lanes.

**Rendering.** Each visible danmaku is a text layer with a 1 pt dark stroke, moved by Core Animation, over the
video and under the controls. Danmaku pause with the video, run faster or slower with the playback speed, are
cleared and re-laid on a seek, and appear in the small player and in full screen. They are not drawn into picture
in picture. The renderer is driven by the player's time, so a stall or seek never desynchronises it.

**Settings (07, 08, 24).** Saved on the phone in `AppSettings`:

| Setting | Values | Default |
|---|---|---|
| 显示区域 | 10%, 25%, 50%, 75%, 100% of the video height | 50% |
| 不透明度 | 10-100% | 100% |
| 字体大小 | 50-200% | 100% |
| 弹幕速度 | 极慢, 较慢, 适中, 较快, 极快 (scroll time 11, 9, 7, 5.5, 4 s across the screen) | 适中 |
| 按弹幕类型屏蔽 | 固定 (top/bottom), 滚动, 彩色 (non-white), 高级 (mode 7, already dropped), 计数 (`×N` merge danmaku) | none |
| 重复弹幕隐藏 | identical text within 10 s shows once | off |
| 底部字幕区域防挡 | bottom danmaku hidden | off |
| 弹幕观看屏蔽词 | apply the cloud block list | on |

人像防挡 is not shown. 添加屏蔽词 > opens a page listing the account's block rules (keywords, regex, users) with add
and delete. ↻ 重置弹幕设置 restores the defaults. The 弹 toggle in the tab row and the player turns danmaku on or off
for every video.

**Block words.** `GET /x/dm/filter/user` loads the account's rules when a page opens (cached for 10 minutes);
add with `POST /x/dm/filter/user/add` (`type` 0 keyword, 1 regex, 2 user hash; `filter`; `csrf`), delete with
`POST /x/dm/filter/user/del` (`ids`, `csrf`). Keywords match by substring, regex rules case-insensitively (strip
surrounding `/`), user rules compare `midHash`. Logged out, the list is empty and 添加屏蔽词 asks to log in.

**Sending (22, 23).** Tapping the danmaku field opens the dark input bar above the keyboard with the A button,
the field (100 characters) and a send arrow. A swaps the keyboard for the style panel: 弹幕字号 默认 (25) / 较小 (18),
弹幕类型 滚动 (1) / 置顶 (5) / 置底 (4), 弹幕颜色: white plus the 13 presets in 23's order, and the 会员 gradient
chip (`colorful=60001`), which is the only 大会员-only choice (23 marks only it 会员). A colour the server refuses
for the account's level shows the server's message. `POST /x/v2/dm/post` with `type=1`, `oid` (cid), `bvid`, `msg`, `mode`, `fontsize`,
`color` (decimal RGB), `progress` (ms), `rnd` (current time in microseconds), `pool=0`, `csrf`. On success the
danmaku shows at once with a white outline box, as the official app marks your own. The style is remembered for
the page. Server errors show their message.

### 4.10 The video page (03, 18, 19)

- Under the player: the tab row 简介 / 评论 N, with "点我发弹幕" and the 弹 toggle at the right (10).
  The tabs also switch by swiping sideways.
- 简介:
  - Uploader row: avatar, name (pink for 大会员), "N粉丝 N视频", pink "+ 关注" (grey "已关注" when following;
    tapping that asks to confirm 取消关注). Videos with several authors (`staff`) show a row of avatars instead.
  - Title with the 活动 tag when the view response has one, and ⌄. Meta line: plays, danmaku, date and time,
    "N人正在看" (polled every 30 s while the page is on top).
  - Expanded (18): the BV id, "⊘ 未经作者授权禁止转载" for original videos (`copyright == 1`), the description
    with links and `mm:ss` timestamps tappable (a timestamp seeks), and tag chips. Tags and the BGM chip are shown
    but not tappable until search exists.
  - Action row: 点赞, 不喜欢, 投币, 收藏, 分享 with counts, filled and pink when active.
  - 合集 row "合集 · 名称" with "N/M >", opening the 合集 sheet (19): title, description with 展开, the playing
    episode pink, 正序/倒序. The 收藏 pill and share in the sheet are left out. Multi-part videos show a 分P strip
    of chips instead, with "选集 N/M >" opening a full list.
  - Related list rows as in 03 and 18. Ads and "立即下载" game cards from the related API are dropped.
- 评论: section 4.12.

### 4.11 Actions

All need a login; logged out, each opens the login screen. Counts update at once and roll back on failure, with
the server's message as a toast.

| Action | Behaviour | Endpoint |
|---|---|---|
| 点赞 | Tap toggles; clears 不喜欢 | `POST /x/web-interface/archive/like` `aid`, `like` (1 like, 2 undo), `csrf` |
| 长按三连 | Hold 点赞: after 0.2 s a ring fills around 点赞, 投币 and 收藏 over 1.2 s; releasing early cancels; completing fires 三连 with a burst; "已三连" if all three are already done | `POST /x/web-interface/archive/like/triple` `aid`, `csrf` |
| 不喜欢 | Tap toggles; clears 点赞. Needs the app token (4.14); without it the button is grey and tapping explains | `POST https://app.bilibili.com/x/v2/view/dislike` `aid`, `dislike` (0 dislike, 1 undo), APP-signed |
| 投币 | The coin dialog (15): two cards 1/2 硬币, ◀ ▶ or swipe to choose, swipe up or tap to throw, the balance, "同时点赞内容" (remembered), ✕. 2 is disabled for reposts (`copyright == 2`), after one coin was given, or with a balance under 2. At the limit: "已投满2个硬币". The mascot and crate art load from Bilibili's web static server; if they fail, our own drawing | `POST /x/web-interface/coin/add` `aid`, `multiply`, `select_like`, `csrf`; balance from `GET https://account.bilibili.com/site/getCoin` |
| 收藏 | A bottom sheet "选择收藏夹": folders with checkmarks (this video's current folders ticked), private folders with a lock, "+ 新建收藏夹" (name and a 私密 switch), 完成 applies the difference | `GET /x/v3/fav/folder/created/list-all` `up_mid`, `rid`, `type=2`; `POST /x/v3/fav/resource/batch-deal` `rid`, `type=2`, `add_media_ids`, `del_media_ids`, `csrf`; `POST /x/v3/fav/folder/add` |
| 分享 | The iOS share sheet with the title and `https://www.bilibili.com/video/<bvid>` (`?p=N` for parts); a completed share is counted | `POST /x/web-interface/share/add` `aid`, `csrf` |
| 关注 | Follow at once; unfollow after a confirm | `POST /x/relation/modify` `fid`, `act` (1, 2), `re_src=14`, `csrf` |
| 稍后再看 | From the ⋮ panel | `POST /x/v2/history/toview/add` `aid`, `csrf` |

The page's starting state comes from `GET /x/web-interface/archive/relation` (`like`, `dislike`, `coin`,
`favorite`, `attention`).

### 4.12 Comments (10-14)

- List: "热门评论" with "☰ 按热度" / "按时间" at the right. The uploader's pinned comment first with a 置顶
  label. Each comment as in 10: avatar with pendant and 大会员 badge, name (pink for 大会员), LV badge, UP badge
  when it is the uploader, the fan-card image at the right when present, text with inline emotes, pictures (tap to
  view full screen with swipe between them), "时间 IP属地", 回复, 👍 count, 👎, ⋮ (复制, and 删除 for your own).
  Under it the preview box with up to two replies and "共N条回复 >"; "UP主觉得很赞" when the uploader liked it.
- Endless scroll, with "没有更多了" at the end. Comments closed: the server's message in place of the list.
- Thread (13): replaces the tab content: 评论详情 with ✕, the root comment, "相关回复共N条" with 按时间/按热度,
  then replies.
- Rich text: emotes (`content.emote`, shown at their size), @names (blue), links in `content.jump_url` (blue;
  video links open the video page, others open in Safari), BV/av ids, and `mm:ss` timestamps that seek.
- Composer (14): the fixed bottom bar "哎呦，不错哦，发条评论吧" with the emote button; tapping opens the white
  composer sheet: placeholder ("回复 名字:" when replying), ○ 转到动态, keyboard/emote toggle, 发布 (pink when
  there is text). @ and ⊕ are left out. The emote panel: 最近使用 (kept on the phone), all emotes in a 7-column
  grid, package tabs along the bottom, the 颜文字 package as text cells. Drafts are kept per comment while the page
  lives.
- Posting: a top-level comment sends no `root`; a reply to a top-level comment sends `root` = `parent` = its rpid;
  a reply inside a thread sends `root` = the thread's rpid and `parent` = the reply's rpid, with the text prefixed
  "回复 @名字 :". The new comment appears at the top of the list or thread at once.

| What | Endpoint |
|---|---|
| List | `GET /x/v2/reply/wbi/main` (WBI) `oid` (aid), `type=1`, `mode` (3 hot, 2 time), `pagination_str` `{"offset":"…"}`; fall back to `/x/v2/reply/main` if the WBI route is refused |
| Thread | `GET /x/v2/reply/reply` `oid`, `type=1`, `root`, `pn`, `ps=20`, `sort` (0 time, 1 hot) |
| Post | `POST /x/v2/reply/add` `oid`, `type=1`, `message`, `root`, `parent`, `sync_to_dynamic`, `csrf` |
| Like / 踩 | `POST /x/v2/reply/action` / `POST /x/v2/reply/hate` `oid`, `type=1`, `rpid`, `action` (1, 0), `csrf` |
| Delete | `POST /x/v2/reply/del` `oid`, `type=1`, `rpid`, `csrf` |
| Emotes | `GET /x/emote/user/panel/web` `business=reply` |

### 4.13 History

- Heartbeat: `POST /x/click-interface/web/heartbeat` with `bvid`, `cid`, `type=3`, `played_time` (whole seconds;
  `-1` at the end), `csrf`. Sent at start, every 15 s of playback, on pause, on seek completion, when the part
  changes, and when the page closes or the app goes to the background. Nothing is sent when logged out. Failures
  are logged and ignored.
- Resume comes from the playurl response (4.1).
- 历史记录 page (28), reached from the home avatar menu: "视频" only (no 直播/专栏/商品/展演 chips), grouped by
  今天 / 昨天 / date, rows with cover, "00:02/02:12" progress on the cover (or 已看完), title, UP, device icon and
  time. Endless scroll. Tapping a row opens the video at that part and position. `GET /x/web-interface/history/cursor`
  `max`, `view_at`, `business=archive`, `ps=20`.

### 4.14 The app token (不喜欢)

The first time 不喜欢 is tapped, a sheet explains that Bilibili needs one confirmation for this action and opens
Bilibili's TV-login confirm page in the in-app web view, which already holds the login cookies:

1. `POST https://passport.bilibili.com/x/passport-tv-login/qrcode/auth_code` (TV app key, `local_id=0`, `ts`,
   `sign`) gives a URL and an `auth_code`.
2. The web view opens that URL; KaiC taps 确认登录.
3. The app polls `POST .../qrcode/poll` every 2 s until it returns `access_token` (or the code expires, then the
   sheet says so and offers to retry).

The TV app key and secret (Bilibili's public client pair) never enter the repo: they come from a GitHub secret
`BILI_APP_KEYS` at build time (written into a generated, gitignored xcconfig and read through Info.plist), in both
`ios-compile.yml` and `testflight.yml`, masked in the log. BiliCore takes the key and secret as parameters; its
signing tests use a made-up pair and the documented algorithm. A build without the secret hides 不喜欢. KaiC adds
the secret in GitHub (the plan gives the click path).

The token is stored in the Keychain beside the cookies, cleared on logout, never logged, and used only for the
app-API call in 4.11. If a dislike call says the token is invalid, the token is dropped and the next tap asks
again. Which app key the dislike request must be signed with (the TV key that issued the token, or another) is
for the builder to confirm on a device.

### 4.15 首页 (01)

- Top row: the avatar at the left (menu: account name and login/logout, 历史记录, 最近打开, 设置); a rounded field
  with the placeholder "粘贴链接或BV号" that opens a pasted link, BV or av id, as M1's paste box does.
- One tab, 推荐, styled as selected; no other tabs and no bottom tab bar.
- A two-column grid of cards on light grey (01): 16:10 cover with play count, danmaku count and duration,
  2-line title, the footer with the 竖屏 tag or "N万点赞" pill or "UP" badge, uploader name, and ⋮ (不感兴趣 is
  left out; ⋮ offers 稍后再看). Ads and live cards from the feed are dropped.
- Pull to refresh, endless scroll. `GET /x/web-interface/wbi/index/top/feed/rcmd` (WBI) `fresh_type=4`, `ps=12`,
  `fresh_idx`, `fresh_idx_1h`, `brush`, `feed_version=V8`.
- The M1 recents list moves behind 最近打开.

## 5. Architecture

### 5.1 BiliCore (package, Foundation-only, `swift test` on Windows)

- `BiliAPI`:
  - POST with a form body and the `csrf` field taken from the `bili_jct` cookie; GET and POST share one request
    path with logging and the -352/-412 handling.
  - Models and calls for every endpoint in section 4 (view with `ugc_season`, `staff`, `desc_v2`, `rights`;
    relation; card; online count; related; tags; player v2 chapters; playurl `last_play_time`/`last_play_cid`;
    actions; favourites; comments; emotes; feed; history; heartbeat; block list; danmaku post).
  - APP signing (`appkey`, `ts`, `sign`) and the TV-login calls.
- New target `Danmaku`: the protobuf reader, `DanmakuElem` model, segment index maths, the filters (type, colour,
  dedupe, block rules, midHash), and the lane layout. No UI.
- New target or folder `RichText` inside `BiliAPI`: turns a comment's `message` plus its emote, member and link
  maps into a list of runs (text, emote, mention, link, timestamp). Rendering is the app's job.
- Pure helpers that need no UIKit also go here: gesture maths (drag to seek seconds, drag to brightness/volume),
  the heartbeat schedule, the autoplay order, quality rules (大会员 qualities, 自动), count formatting (1.2万).

### 5.2 App

- `Player/`: `PlayerView` (UIKit view hosting `AVPlayerLayer`, the danmaku layer and the gesture recogniser, wrapped
  for SwiftUI), the chrome views for portrait, landscape and 竖屏, pickers and panels, PiP controller,
  orientation control (a scene-level supported-orientations value plus `requestGeometryUpdate`), brightness and
  volume control, the screenshot capture (`AVPlayerItemVideoOutput`).
- `Danmaku/`: the renderer, the settings panel, the block-word page, the send bar.
- `VideoPage/`: the page, 简介, action row and dialogs (coin, favourites, share), 合集/分P sheets, related list.
- `Comments/`: list, thread, comment row, composer, emote panel, picture viewer.
- `Home/`: the new 首页 and feed; `History/`: the 历史记录 page.
- `PlaybackController` keeps owning playback (BTR, direct, fallback, quality, codec); it gains rate, part switching
  and time observation for danmaku, heartbeat and chapters. `PlayerScreen` and `VideoPlayerView` are replaced.
- Images (covers, avatars, emotes, pendants) load through one small cached image loader on `URLSession` (memory
  plus disk cache), with the `Referer` header Bilibili's image servers expect. No third-party image library.
- Photos permission for the screenshot button: add-only (`NSPhotoLibraryAddUsageDescription`).

## 6. Failure handling

- Any API failure on the page shows inline (a retry row in the list, or a toast for actions) and never blocks
  playback.
- Risk-control codes (-352, -412) are logged with the endpoint; the user sees "请求过于频繁，请稍后再试".
- A danmaku segment failure leaves danmaku empty for that segment; playback goes on.
- A heartbeat failure is logged only.
- PiP start failure leaves inline playback as it was.

## 7. Security and privacy

- The app token is a credential like the cookies: Keychain only, never logged; the `Redactor` masks
  `access_key`, `access_token`, `csrf` and `sign` values in logged URLs and bodies.
- Heartbeats write to KaiC's own Bilibili history, as KaiC chose. Nothing else leaves the phone except the
  requests the features need.
- No art, icon or code from Bilibili's app or PiliPlus enters the repo. The coin dialog art is fetched at run time
  from Bilibili's servers and cached like any image.

## 8. Testing

- BiliCore unit tests: protobuf decoding (fixtures built in the tests), segment index maths, every filter, lane
  layout (no overlap, drops when full, area limit), rich-text runs, request building and signing for each new
  endpoint (form fields, csrf, WBI, APP sign), heartbeat schedule, autoplay order, gesture maths, count formatting.
- App simulator tests that perform each system transition, per the repo rule: entering and leaving landscape full
  screen (button and orientation), 竖屏 full screen, starting PiP, presenting and dismissing the coin dialog,
  favourites sheet, share sheet, composer, ⋮ panel, pickers and the TV-login sheet.
- Demo data (`#if DEBUG` launch arguments) for every new screen, screenshotted by the compile check: home feed,
  video page (简介, expanded, 合集 sheet), comments, thread, composer with emotes, coin dialog, favourites sheet,
  landscape player with controls, each picker and panel, 竖屏 full screen, end screens, history.
- Phone checklist per build in `docs/m2-phone-checklist.md`.

## 9. Build and ship

- Build A ships when: the player, gestures, pickers, ⋮ panel, full screen (both kinds), PiP, chapters, end screen,
  danmaku (show, settings, block words, send) and history reporting work on the phone, and BTR stats still show.
- Build B ships when: the page, all actions, comments, related, 合集/分P, the app token, home and history page work.
- Each build: compile check green and screenshots looked at, then TestFlight, then KaiC's checklist run.

## 10. Risks

| Risk | What we do |
|---|---|
| Web POST actions hit risk control (-352) for a native client | Send the browser user agent, `Origin`/`Referer` of the video page, and the cookies the web sends; log codes; if one action keeps failing on the phone, fix that call in build B's tail |
| The TV-login token doesn't work for dislike | 不喜欢 stays grey with an explanation; nothing else depends on it |
| `x/v2/reply/wbi/main` refuses us | Fall back to `/x/v2/reply/main` |
| Coin art URLs move | Our own drawing is the fallback |
| Danmaku rendering costs frames at 4K with heavy danmaku | Cap visible danmaku per lane set, reuse layers, measure on the phone; the engine runs off the main thread already |
| Rotation and PiP with a custom layer crash like build 1's full screen did | Simulator tests for every transition (section 8) |
| Hidden `MPVolumeView` slider behaviour changes in an iOS update | Volume gesture degrades to doing nothing; logged |

## 11. Left to the builder

- Exact sizes, paddings and font weights, read from the screenshots.
- Whether danmaku layers are `CATextLayer` or prerendered images, as long as 4.9's behaviour holds.
- The coin art URLs on Bilibili's static server.
- The 活动 tag's source field in the view response (if none is found, no tag).
- Which app key signs the dislike call.
- Task order inside each build, as long as build A ships before build B starts.
