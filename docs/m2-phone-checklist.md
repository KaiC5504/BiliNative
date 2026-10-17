# Milestone 2: phone checklist

The app is called **BiliFast** on the phone. UI labels below are in Chinese, exactly as shown in the app. Keep the PC log receiver running while you test (`uv run tools/logserver.py`, then 设置 → 开发者 → 发送日志到电脑), so anything odd can be read from `logs/` afterwards.

## Build A: the player

Build A replaces the M1 test player with the official-style player. The page under the player only shows the title and the 分P chips; likes, comments and related videos come in build B.

### Opening and resuming

1. In the official app: Share → Copy link on any video. In BiliFast tap 粘贴 on the home screen. The video page opens and plays.
2. Go back and open the same video from 最近打开. It opens again.
3. In the official app, watch a different video to about the middle and close it. Open it in BiliFast. It starts where you stopped in the official app (give or take a few seconds).
4. Open a video you finished in the official app. It starts at 0.

### Small player (portrait)

5. Tap the video: the controls show (back, ⋮, play, the bar with the little TV face, time, 竖屏, full screen). Wait 3 seconds without touching: they hide and a thin pink line stays at the bottom.
6. Double-tap: pauses. Double-tap again: plays.
7. Press and hold: "倍速中" shows at the top and the video plays at 2×. Let go: back to normal speed.
8. Drag left or right across the video: a time label shows; let go and it jumps there (a full-width drag is 90 seconds).
9. Drag up or down on the video: the page scrolls; brightness and volume do not change in the small player.
10. Drag the bar's TV face: the video jumps where you let go. On a video with chapters (看点), ticks show on the bar and the chapter title shows while dragging.

### Full screen

11. Turn the phone sideways: the player goes full screen. Turn it back: it returns to the small player.
12. Tap the full-screen button: full screen. Tap back (top left): small player.
13. In full screen, drag up and down on the left half (brightness) and the right half (volume): an indicator shows in the middle and the system volume HUD does not.
14. Tap the rotation lock on the right edge, then turn the phone upright: it stays sideways. Unlock, turn upright: it returns.
15. Tap 竖屏 in the small player: the video plays full screen upright with the 竖屏 controls. Back returns to the small player.
16. Open a vertical (portrait) video. Turn the phone sideways: nothing changes. Its full-screen button opens the upright 竖屏 view.
17. Tap the screenshot button on the right edge in full screen. Allow Photos access the first time. A toast says 已保存到相册 and the frame is in Photos.

### Panels

18. Tap the quality name (full screen): the 清晰度 panel slides in from the right. Pick a lower quality: it switches and keeps playing. 大会员 rows are pink-badged. Tap 高级设置: pick another 编码; it switches.
19. Tap 倍速: pick 1.5X; it plays faster. The speed stays when the next part plays.
20. Tap ⋮: try every row.
    - 稍后再看: toast 已添加至稍后再看; the video is in 稍后再看 in the official app.
    - 小窗播放: picture in picture starts.
    - 定时关闭 → 自定义 → 1 minute: the video pauses after a minute.
    - 自动连播, 循环播放 (单集循环 replays the video at the end), 镜像翻转 (the picture flips), 画面尺寸 (适应, 填充, 拉伸, 16:9, 4:3).
    - 测试 card: BTR 加速 switches the mode pill in the stats; 显示统计 shows or hides the stats box.
21. Every panel closes when you tap outside it, in full screen and in the small player.

### Picture in picture

22. While a video plays, swipe home: it keeps playing in a small window. Tap the window's button to return to the app.
    - With the small window off, swipe home: the sound stops (no background audio).

### Ends and autoplay

23. Seek to a few seconds before the end of a video in a 合集 with 自动连播 on: the next episode plays on the same page.
24. Turn 自动连播 off and let a video end: the end screen shows (推荐视频 with 立即播放, 重播 and 分享 in the small player; the uploader, 重播 and related videos in full screen). 分享 opens the iOS share sheet with the video link.
25. On a multi-part video, open 选集 in full screen and pick another part: it plays.

### Danmaku

26. Danmaku fly across the video. None overlap. They follow the video: pause stops them, a seek clears and restarts them, 2× speeds them up.
27. 弹 toggles them off and on.
28. 弹幕设置: change 显示区域, 不透明度, and under 查看更多 字体大小 and 弹幕速度; each change shows at once. Try each 按弹幕类型屏蔽 square, 重复弹幕隐藏 and 底部字幕区域防挡. ↻ 重置弹幕设置 puts everything back.
29. 添加屏蔽词: add a word that appears in the danmaku: those danmaku disappear. Check 弹幕屏蔽 in the official app's settings: the word is there. Delete it in BiliFast; it is gone from the official app too.
30. Tap the danmaku field in full screen, type something and send: it appears at once with a white outline box. Tap A and send one in another colour, size and position (top or bottom). 会员 colours work with 大会员.

### History and speed

31. After watching a while, check 历史记录 in the official app: the video is there at about the position you stopped.
32. The stats box still shows BTR. First frame and 卡顿 feel the same as in M1.

## Before build B

Build B's 不喜欢 button needs Bilibili's public TV-client key and secret. They stay out of the repo: GitHub holds them as a secret and each build writes them into the app. Do this once, on the PC, before build B ships. It takes about three minutes. Without it everything still builds, and 不喜欢 stays grey with an explanation.

1. Open the bilibili-API-collect page `docs/misc/sign/APPKey.md` (GitHub: SocialSisterYi/bilibili-API-collect). Find the row whose platform is the TV client (云视听小电视, the appkey starts with `4409e2ce`) and copy its appkey and appsec.
2. In a terminal in the repo run `gh secret set BILI_APP_KEYS -R KaiC5504/BiliNative`. When it asks, paste `appkey:appsec` on one line, with a colon between the two.
3. Check with `gh secret list -R KaiC5504/BiliNative` that `BILI_APP_KEYS` is in the list.

To see that it worked: in the next "iOS compile check" run, the "App keys" step says `app keys written` and shows no values. Without the secret it shows a notice that `BILI_APP_KEYS` is not set.

## Build B: the page and the entry points

Build B adds the 首页 feed, 历史记录, the full video page (简介, actions, comments) and the player fixes for pages stacked on pages. Keep the log receiver running as for build A.

### Picture in picture and stacked pages

33. Play a video, tap ⋮ → 小窗播放, then tap back (top left) to leave the page. The small window keeps playing.
34. Tap the small window's restore button: the same video page opens again at the same place, without a reload, and the video moves from the small window back into the player.
35. Start the small window again and leave the page. Tap ✕ on the small window: it closes and the sound stops. Open any video: it plays normally.
36. Start the small window and leave the page, then open another video: the small window closes before the new video starts.
37. On a 合集 or multi-part video with 自动连播 on, seek to a few seconds before the end, start the small window and swipe home. At the end the next episode plays inside the small window.
38. On a video page, open a related video under the player: the first video pauses. Go back: it carries on from where it was, without a reload. 弹幕设置 → 添加屏蔽词 in the small player does the same: back resumes the video.
39. Open a related video, start the small window on it, and go back: the small window keeps playing and the first video stays paused. Tap play on the first video: the small window closes.
40. On a related video page, start the back swipe from the left edge, drag halfway and let go so the page springs back: it keeps playing and turning the phone still works. Then swipe all the way back: the first video carries on and the second stops.
41. Open a related video, start the small window on it, go back to the first video, and tap the small window's restore button: the second video's page opens on top of the first, at the same place, and going back from it returns to the first video (still paused).
42. Open a vertical video, then a related landscape video, then go back: turning the phone sideways on the vertical video does nothing, as in step 16. On the landscape video page, turn sideways (full screen) and swipe right from the left edge: if the page closes, the previous page shows upright.

### 首页 and 历史记录

43. Open the app: the 推荐 feed shows two columns of cards with play counts, duration and the uploader. Pull down: it refreshes with new cards. Scroll down a long way: more cards keep loading, with no repeats.
44. On a card, ⋮ → 稍后再看: a toast says it was added; it is in 稍后再看 in the official app.
45. Paste a video link into 粘贴链接或BV号 (or tap the paste button): the video opens, as in build A.
46. Tap the avatar: the menu shows your name and 大会员, 历史记录, 最近打开 and 设置. 历史记录 lists today's and yesterday's videos under 今天 and 昨天 with a progress bar on each cover; a finished one says 已看完. Tap one: it opens at that position (a finished one at the start). Pull down to refresh: the list stays while it reloads. 最近打开 shows the build A list.

### The video page

47. Under the player: 简介 and 评论 tabs; swipe sideways to switch. The uploader row shows the avatar, name, fans and videos, and 关注.
48. Tap the title's ⌄: the BV id, the description and the tags show. A time like 03:15 in the description seeks the player; a web address opens Safari.
49. On a 合集 video tap the 合集 row: the sheet lists the episodes with the playing one pink; pick another: it plays. On a multi-part video, the 选集 chips and the full list both switch parts.
50. Pause and scroll the page up: the player shrinks to a thin bar with 继续播放; tap it: the page scrolls back and plays. While playing, the player never shrinks. When the video ends, the end screen stays visible.
51. Tap a related video: it opens on top; back returns to the first one (see step 38).
52. Tap 点我发弹幕 next to the tabs: the danmaku bar opens above the keyboard in the small player and sends as in step 30.

### Actions

53. Logged in: tap 点赞 (it turns pink and the count goes up), tap again (it goes back). Hold 点赞 for about 1.5 s: rings fill around 点赞, 投币 and 收藏, then all three turn pink (三连). Let go early: nothing happens, and the like doesn't toggle.
54. 投币: the coin dialog shows the two crates, 22娘 and your balance. Pick 1 or 2 with the arrows or a sideways swipe, then swipe up or tap 22娘: the coin flies and 投币 turns pink. 同时点赞内容 also likes. Check the coins in the official app.
55. 收藏: tick a folder and untick another, then 完成; check both folders in the official app. + 新建收藏夹 with a name (and 私密 on): the new folder appears ticked.
56. 分享 opens the iOS share sheet; share somewhere: the share count goes up.
57. 关注: it changes to 已关注. Tap again: "确定不再关注？" asks first; 确定 unfollows.
58. In landscape full screen and in 竖屏, the action icons work the same, and 评论 brings you back to the small player on the 评论 tab.
59. Log out (设置) and tap each action: the login screen comes up and nothing is sent. From landscape full screen, the phone turns upright first and then the login screen shows.

### 不喜欢

60. If the `BILI_APP_KEYS` secret was not added (see "Before build B"), 不喜欢 is grey and says 此版本不支持不喜欢. Skip to step 62.
61. With the secret: tap 不喜欢. A sheet explains it needs one confirmation; tap 「确认登录」 on the page inside it. The sheet closes and 不喜欢 turns on. Tap again: it turns off. If it fails, note the toast text: the call may need changes (`docs/background.md`).

### Comments

62. 评论 tab: comments with avatars, VIP names in pink, LV badges, pictures and emotes. Switch 按热度 / 按时间: the list reloads in the new order. Scroll to the end: 没有更多了.
63. Tap 共N条回复 under a comment: the thread opens with 评论详情 and ✕; switch its sort and scroll it. Tap a picture: it opens full screen; swipe between pictures; tap to close.
64. Like a comment, then 踩 one; both toggle back. On your own comment, ⋮ → 删除 asks first and removes it.
65. Tap 哎呦，不错哦，发条评论吧: the composer opens with the keyboard. Type something, add emotes from the emote button (最近使用 fills as you use them), and 发布: the comment appears at the top. Check it in the official app.
66. 回复 on a comment and on a reply inside a thread: the reply shows "回复 @name :" where it should, and appears in the official app under the right comment. Close the composer and reopen it: your unsent text is still there.

### Memory

67. Open 10 or so videos one after another from related videos and go back to the first each time. The app stays smooth and nothing keeps playing in the background.

Tell Claude which steps failed and roughly when; the logs have the rest.
