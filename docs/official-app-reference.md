# Official app reference screens

KaiC's screenshots of the official Bilibili iOS app (iPhone 17 Pro Max, 2026-10-16). They are the visual target
for milestone 2 and later. The images are Bilibili's and stay out of this public repo. They live in
`local/official-app-reference/` (gitignored); read them with the Read tool before building a screen. Copy layout, spacing,
order and colours; never the Bilibili logo or wordmark (project rule).

Shared look:
- Pink accent (about `#FB7299`) for the selected tab, selected values, active toggles, badges and the main button.
- White background in portrait, with grey secondary text.
- The landscape player and its panels are black, with white text and dark-grey rounded cards on the right.

| File | Screen |
|---|---|
| `01-home.png` | 首页 (home feed) |
| `02-me.png` | 我的 (me) |
| `03-video-detail-portrait.png` | Video page, portrait |
| `04-player-landscape.png` | Player, landscape, controls showing |
| `05-player-quality-picker.png` | 清晰度 picker (landscape) |
| `06-player-speed-picker.png` | 倍速 picker (landscape) |
| `07-danmaku-settings-top.png` | 弹幕设置 panel, top half |
| `08-danmaku-settings-bottom.png` | 弹幕设置 panel, bottom half |
| `09-vertical-video-fullscreen.png` | 竖屏 video, full screen (portrait) |
| `10-comments.png` | 评论 tab |
| `11-comments-scrolling-player-shrinks.png` | 评论 tab scrolled while paused: the player shrinks |
| `12-comments-fully-scrolled.png` | Player collapsed to a 继续播放 bar |
| `13-reply-thread.png` | 评论详情 (reply thread) |
| `14-comment-composer-emotes.png` | Reply composer with the emote panel |
| `15-coin-dialog.png` | 投币 dialog over the video page; also the portrait player's controls |
| `16-favourite-folders.png` | 我的收藏, folders (milestone 4 screen) |
| `17-favourites-by-videos.png` | 我的收藏, videos (milestone 4 screen) |
| `18-intro-expanded.png` | 简介 with the title expanded |
| `19-collection-list.png` | 合集 sheet |
| `20-landscape-more-menu-1.png` | ⋮ panel in landscape, top |
| `21-landscape-more-menu-2.png` | ⋮ panel in landscape, bottom |
| `22-danmaku-input.png` | Landscape danmaku input with the keyboard |
| `23-danmaku-input-style.png` | Danmaku style panel (the A button) |
| `24-danmaku-settings-more.png` | 弹幕设置 after 查看更多 |
| `25-hold-speed-up.png` | Hold-to-speed-up indicator |
| `26-video-end-portrait.png` | End of a video, portrait |
| `27-video-end-landscape.png` | End of a video, landscape |
| `28-watch-history.png` | 历史记录 (milestone 4 screen) |

## 01 首页

- Top row: the avatar on the left, then a rounded search field with grey placeholder text (a trending query).
- Category tabs under it: 直播, 推荐 (selected: pink, bold, pink underline bar), 热门, 动画, 影视.
- Feed: a two-column grid of white cards on a light grey background.
- Each card:
  - A 16:10 cover with a dark bottom gradient. On it sit play count (▶ 9.1万), danmaku count, and duration at the
    right.
  - A 2-line title.
  - A footer line: a pink tag (竖屏, or "2万点赞" on a pink tint) or an "UP" badge, the uploader name in grey, and
    a ⋮ menu.
  - Ad cards say 创作推广 at the cover's right.
- Bottom tab bar: 首页 (pink when selected), 关注, a raised pink rounded "+" button in the middle, 消息, 我的.

## 02 我的

- Top-right icons: TV cast, scan, outfit, dark mode.
- Header:
  - A large round avatar with a pink 大 badge.
  - The name in pink with an edit pencil and a level badge (LV5).
  - A pink 年度大会员 pill.
  - B币 and 硬币 counts.
  - 空间 > at the right.
- Stats row: 动态 / 关注 / 粉丝 counts, with thin dividers.
- A pink-tinted 续订会员 card with a pink 会员中心 button.
- Four shortcuts: 离线缓存, 历史记录, 我的收藏, 稍后再看 (blue outline icons).
- A 发布你的第一个视频 card (UP badge, pink 有奖发布 button).
- 我的服务: a 4-column grid of pink outline icons. 更多服务 is a list (联系客服 >).

## 03 Video page, portrait

- Player across the full width at the top (16:9). The status bar area is black.
- Optional ad row under the player (app promo, 广告 · 评分, ⋮).
- Tabs: 简介 (pink underline) and 评论 213, with a round danmaku toggle button (弹) at the right.
- Uploader row: avatar with a badge, the name in pink, 粉丝 and 视频 counts, and a pink 关注 pill at the right.
- Title: a pink 活动 tag, the bold title, and a ⌄ to expand.
- Meta line: play count, danmaku count, date and time, and "N人正在看".
- Action row:
  - 点赞 with count; 不喜欢 (label only).
  - 投币 with count, 收藏 with count, and 分享 with count.
  - Icons are dark grey and filled.
- 合集 row: "合集 · MAD系列" with an episode counter (221/221 >).
- Topic chips: music, a related film, a tag.
- Related list: thumbnail with duration, a 2-line title, a pink tag (热门日本电影榜 NO.6, 18万投币), the
  uploader, play and like counts, and ⋮.

## 04 Player, landscape

- Top bar, left to right:
  - Back chevron.
  - Title in one line.
  - Under the title, "1人正在看", then the uploader avatar and "+ 关注".
- Top right, a row of outline icons: 点赞 (count as a superscript), 评论, 收藏 (count), 投币, 充电, 分享, ⋮.
- Right edge, vertically centred: a screenshot button and a rotation-lock button.
- Bottom-left: time "00:07/13:14" above the bar.
- Progress bar:
  - Thin, pink played part.
  - The thumb is a small TV-face icon (the Bilibili mascot style: draw our own, no logo).
- Bottom row:
  - Play/pause.
  - Danmaku on/off (弹 with a check).
  - Danmaku settings (弹 with a gear).
  - A wide rounded danmaku input "发个友善的弹幕见证当下".
  - 倍速 text button, then the quality text button (4K).
- Top-right status: WIFI pill and battery.

## 05 清晰度 picker

- A right-side panel on black. Header 清晰度, with 高级设置 > at the right.
- Rounded dark cards, one per option:
  - 自动.
  - HDR 真彩 with a pink 大会员 pill, a ⓘ, and the subtitle 绚丽色彩，沉浸体验.
  - 4K 超高清 (selected: pink text) with 大会员.
  - 1080P 60帧 with 大会员.
  - 1080P 高清.
  - 720P 准高清, and so on.

## 06 倍速 picker

- No panel, just a right-aligned column of text on the dimmed video: 3.0X, 2.0X, 1.5X, 1.25X, 1.0X (selected,
  pink), 0.75X, 0.5X.

## 07-08 弹幕设置 panel

- A right-side panel, scrollable. Header 弹幕设置, with 查看更多 ⌄.
- Card 1, two sliders:
  - 显示区域: 10% with 5 stops.
  - 不透明度: 100%, pink track.
- 画面防挡 section:
  - 按弹幕类型屏蔽: five square icon buttons, 固定 / 滚动 / 彩色 / 高级 / 计数.
  - Toggles with subtitles: 重复弹幕隐藏 (大量内容相同的弹幕会被隐藏), 底部字幕区域防挡 (底部弹幕会被隐藏),
    and 人像防挡 (人像不被弹幕遮挡，部分视频生效; pink, on).
- 更多工具:
  - 弹幕观看屏蔽词 toggle (仅对我不展示特定弹幕).
  - 添加屏蔽词 >.
  - 当前弹幕列表 >.
- Footer: ↻ 重置弹幕设置.

## 09 竖屏 video, full screen

- Black page, video centred in the middle band.
- Top: back chevron, "479人正在看", search and ⋮ at the right.
- Right column, stacked: 点赞, 评论, 投币, 收藏, 分享, each a large white filled icon with its count under it.
- Bottom-left: uploader avatar, pink name, "6129粉丝", pink 关注 pill. Under it the title in two lines, ending with
  "5.6万播放 ⌄".
- A dark rounded search suggestion row ("搜索 • …  >"), then a thin progress bar with a white dot.
- Bottom row: a dark rounded "发弹幕" field with the 弹 toggle inside its right end, then a 详情页 button (shrink
  arrows with a "详情页" pill above) and a full-screen button.

## 10-12 评论 tab and the shrinking player

- Tab row: 简介, 评论 242 (pink, underlined). At the right a grey rounded "点我发弹幕" field joined to the 弹 toggle.
  This field replaces the plain 弹 button whenever danmaku can be sent.
- Header row: 热门评论 at the left, "☰ 按热度" at the right (switches to 按时间).
- A comment:
  - Avatar (with a pendant frame and a pink 大 badge for 大会员), pink name for 大会员 (grey otherwise), an LV6 badge,
    and an optional fan-card image with a number (NO. 017949) at the far right.
  - Text with inline emotes; optional pictures.
  - Meta line: "1小时前 湖北", 回复, then 👍 60, 👎, ⋮.
  - A light grey rounded box under it with up to two preview replies ("HYSSNH: …  👍 51") and a blue
    "共12条回复 >".
- Bottom bar fixed on screen: a grey rounded "哎呦，不错哦，发条评论吧" field and an emote button.
- Scrolling while paused shrinks the player (11), then collapses it to a short dark bar with back, "▶ 继续播放"
  and ⋮ (12). Tapping 继续播放 expands it and plays.

## 13 评论详情

- Replaces the tab content under the player: header 评论详情 with an ✕.
- The root comment in full, then a grey divider band, then "相关回复共12条" with "☰ 按时间" at the right.
- Replies use the same row layout without the preview box.

## 14 Reply composer

- A white sheet over a dimmed page. Placeholder "回复 殇泪丶丿:", an expand arrow at the top right.
- Toolbar: ○ 转到动态, keyboard/emote toggle (pink when the emote panel shows), @, ⊕, and a pink 发布 button
  (faded until there is text).
- Emote panel: 最近使用, then 所有表情 in a 7-column grid. Package tabs along the bottom (settings, search, recent,
  then each package; one is a 颜文字 text package).

## 15 投币 dialog and the portrait player controls

- The page dims. Two wooden-crate cards, "1 硬币" and "2 硬币" (the selected one larger), with ◀ ▶ arrows.
  A mascot character runs up from below with the text "上滑或点击22娘投硬币" and "硬币余额：873.0".
  Bottom: "☑ 同时点赞内容" at the left, a round ✕ in the middle, "如何获取硬币？" at the right.
  The mascot and crates are Bilibili's art: draw our own.
- Portrait player controls (tap the small player): back at the top left; 听 (audio only) pill, TV cast and ⋮ at the
  top right. Bottom row: play, the progress bar with the TV-face thumb, "00:01/03:15", a 竖屏 full-screen button
  (corner brackets with a 竖屏 pill) for vertical videos, and the full-screen button.

## 18 简介 expanded

- Tapping ⌄ (now ⌃) shows under the stats: the BV id, "⊘ 未经作者授权禁止转载", the description, and tag chips
  (必剪创作).
- A topic chip row ("# 下: 星穹铁道创作者激励计划 >") above the related list.
- Related list rows: thumbnail with duration, 2-line title, "UP 顾念2341", play and danmaku counts, ⋮.

## 19 合集 sheet

- A sheet over the page below the player, with a grabber. Title "MAD系列", ✕.
- Description with 展开, a share button and a pink "☆ 收藏" pill (subscribe to the collection).
- 选集 header with "正序" sort at the right.
- Rows: thumbnail with duration, title, date, play and danmaku counts. The playing one is pink with a bars icon.
- Footer: 内容到底啦.

## 20-21 ⋮ panel (landscape)

- A right-side dark panel:
  - Four square buttons: 听视频, 稍后再看, 小窗播放, 投屏.
  - 定时关闭: a segmented row 不开启 (pink) / 15:00 / 30:00 / 60:00 / 自定义.
  - A card of rows: 自动连播 (toggle), 循环播放 (单集循环 / 列表循环 / 不循环), 镜像翻转 (toggle), 后台听视频 (toggle),
    画面尺寸 (适应 >), 色觉辅助 (不开启 >).
  - A second card: 播放反馈 >, 编辑播放器 >.

## 22-23 Danmaku input (landscape)

- Tapping the danmaku field opens a dark bar above the keyboard: an "A" style button, the white rounded field
  "发个友善的弹幕见证当下", and a send arrow. The video stays visible above.
- The A button swaps the keyboard for a style panel:
  - 弹幕字号: 默认 (selected, pink) / 较小.
  - 弹幕类型: 滚动 / 置顶 / 置底.
  - 弹幕颜色: white (selected), a 会员 gradient chip, then red, yellow, green, blue, magenta, lime, navy, orange,
    purple, light blue, olive.

## 24 弹幕设置, 查看更多

- The first card gains 字体大小 (88%, a continuous pink slider) and 弹幕速度 (5 stops, 适中 in the middle).

## 25 Hold to speed up

- A dark rounded pill at the top centre: "⏩ 倍速中". Controls stay hidden.

## 26-27 End of a video

- Portrait: the player dims with "推荐视频" and one card (thumbnail with play button, title, UP, counts) and a
  "立即播放" button; bottom-left 重播 and 分享.
- Landscape: back at the top left; uploader avatar, name, 充电 (outline) and 关注 (pink); at the right 重播 | 点赞,
  投币, 收藏, 分享. Below, "推荐视频" as a horizontal row of large cards with counts and duration on the cover.

## 16-17, 28 Milestone 4 screens

- 我的收藏: tabs 收藏 / 追更; chips 收藏夹 / 视频; folder cards with three covers and "N个内容 >"; 新建收藏夹.
- 历史记录: chips 全部 / 视频 / 直播 / 专栏 / 商品 / 展演; grouped by day; rows with the progress "00:02/02:12" on the
  cover, the UP, and a device icon with the time.

## Notes for building

- The gestures KaiC asked for (2026-10-16) aren't visible in the screenshots:
  - double-tap to pause or play;
  - long-press for 2× while held;
  - horizontal swipe to seek;
  - vertical swipe on the left for brightness and on the right for volume.
- AVPlayerViewController's own chrome can't look like 04-08. Milestone 2 needs a custom player overlay over an
  `AVPlayerLayer`, keeping PiP through `AVPictureInPictureController`.
- 人像防挡 needs Bilibili's per-video mask data. Leave it out unless the API exposes it.
