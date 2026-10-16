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
    - Known in build A: leaving the video page while the small window is open closes it, and in the small window a 合集 stops at the end of the episode instead of playing the next one. Both come in build B.
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

Tell Claude which steps failed and roughly when; the logs have the rest.

## Before build B

Build B's 不喜欢 button needs Bilibili's public TV-client key and secret. They stay out of the repo: GitHub holds them as a secret and each build writes them into the app. Do this once, on the PC, before build B ships. It takes about three minutes. Without it everything still builds, and 不喜欢 stays grey with an explanation.

1. Open the bilibili-API-collect page `docs/misc/sign/APPKey.md` (GitHub: SocialSisterYi/bilibili-API-collect). Find the row whose platform is the TV client (云视听小电视, the appkey starts with `4409e2ce`) and copy its appkey and appsec.
2. In a terminal in the repo run `gh secret set BILI_APP_KEYS -R KaiC5504/BiliNative`. When it asks, paste `appkey:appsec` on one line, with a colon between the two.
3. Check with `gh secret list -R KaiC5504/BiliNative` that `BILI_APP_KEYS` is in the list.

To see that it worked: in the next "iOS compile check" run, the "App keys" step says `app keys written` and shows no values. Without the secret it shows a notice that `BILI_APP_KEYS` is not set.
