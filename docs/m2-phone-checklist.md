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

## Build B: the page and the entry points

(Task 27 fills in the rest of this section.)

### Picture in picture and stacked pages

33. Play a video, tap ⋮ → 小窗播放, then tap back (top left) to leave the page. The small window keeps playing.
34. Tap the small window's restore button: the same video page opens again at the same place, without a reload, and the video moves from the small window back into the player.
35. Start the small window again and leave the page. Tap ✕ on the small window: it closes and the sound stops. Open any video: it plays normally.
36. Start the small window and leave the page, then open another video: the small window closes before the new video starts.
37. On a 合集 or multi-part video with 自动连播 on, seek to a few seconds before the end, start the small window and swipe home. At the end the next episode plays inside the small window.
38. On a video page, open a related video under the player: the first video pauses. Go back: it carries on from where it was, without a reload. 弹幕设置 → 添加屏蔽词 in the small player does the same: back resumes the video.
39. Open a related video, start the small window on it, and go back: the small window keeps playing and the first video stays paused. Tap play on the first video: the small window closes.
40. Open a vertical video, then a related landscape video, then go back: turning the phone sideways on the vertical video does nothing, as in step 16. On the landscape video page, turn sideways (full screen) and swipe right from the left edge: if the page closes, the previous page shows upright.

Tell Claude which steps failed and roughly when; the logs have the rest.
