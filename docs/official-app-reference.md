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

## Notes for building

- The gestures KaiC asked for (2026-10-16) aren't visible in the screenshots:
  - double-tap to pause or play;
  - long-press for 2× while held;
  - horizontal swipe to seek;
  - vertical swipe on the left for brightness and on the right for volume.
- AVPlayerViewController's own chrome can't look like 04-08. Milestone 2 needs a custom player overlay over an
  `AVPlayerLayer`, keeping PiP through `AVPictureInPictureController`.
- 人像防挡 needs Bilibili's per-video mask data. Leave it out unless the API exposes it.
