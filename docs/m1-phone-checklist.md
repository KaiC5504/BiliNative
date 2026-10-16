# Milestone 1: phone checklist

The app is called **BiliFast** on the phone. UI labels below are in Chinese, exactly as shown in the app.

## Setup

1. On the PC run `uv run tools/logserver.py`. If Windows asks about Python, allow it on private networks. The PC and phone must be on the same Wi-Fi.
2. Install BiliFast from TestFlight and open it.
3. Tap the gear (top right) → under 开发者 turn on 发送日志到电脑. When iOS asks to find devices on your local network, tap Allow.
4. Tap your PC in the list under the switch. A checkmark appears next to it and the line below says 已连接, and the PC window starts printing lines.
   - The PC prints two addresses. 192.168.50.201 is the home Wi-Fi. 192.168.137.1 is a hosted-network adapter and the phone cannot reach it. If you have to type an address, use `192.168.50.201:47321` in 或手动输入 IP:端口 and press return.
5. Tap 完成. On the home screen, tap 登录哔哩哔哩 and log in as usual. The account row should show your name with a pink 大会员 badge.

## Measure each video

Pick three videos that stutter in the official app (cold, 4K or high bitrate). Everything below is done once per video. The mode order and the seek positions change per video (the Results table says which), so neither mode always gets the warm start or the same cached parts.

**Why 编码 matters:** BTR and direct must play the same stream or the comparison means nothing. So for the two main runs set 编码 to **H.264** (or **AV1** if H.264 is greyed out or fails; use the same one for all three videos). The extra HEVC row at the end is the only run on HEVC.

**Seeking rule:** a seek only counts if you drag the bar to a part that is not loaded yet (past the grey buffered area). If 跳转恢复 shows about 0.00 秒, that part was already loaded: don't count it, seek further ahead and write down the new one. Seek with one drag, then wait for playback to resume before the next one.

1. Official app first. Do this for at least video 1, better for all three. In the official app play the video and time with a stopwatch: tap to first frame, then one seek (drag the bar to 50%). Write both times in the official app row.
2. In the official app: Share → Copy link. In BiliFast tap 粘贴 on the home screen. The player opens.
3. In the list under the video set 编码 to H.264 (or AV1). Set BTR 加速 on or off for the first run of this video (the table says which).
4. Tap back, then tap the same video under 最近打开. It reopens at 0 with the toggle and 编码 you just saved. Wait for the first frame.
5. Check the pill under the video: BTR (pink) when 加速 is on, 直连 (blue) when it is off. If it says 直连（回退） in a BTR run, note it and tell Claude.
6. Write down from the stats box: 首帧, 画质, and the **codec shown on the 画质 line** (for example `1080P 高码率 · HEVC · 2.1 Mbps`). If the codec is not the one you picked in 编码, write down what it shows.
7. Seek three times, using the percentages for this run (see Results): drag the bar to that position. After each, write down 跳转恢复.
8. Let it play for 2 minutes without touching it. Write down 卡顿 (the 次 count).
9. Flip the BTR 加速 switch for the second run and repeat steps 4-8 on the same video with the other seek percentages. Do not skip step 4: reopen from 最近打开 so 首帧 starts at 0.
10. After the video's two runs, turn BTR 加速 back on.
11. Video 1 only, extra run: BTR 加速 on, 编码 set to HEVC, reopen from 最近打开, write down 首帧, one seek (50%), and 卡顿. This shows what BTR does on the stream it will play by default.

## Results

Pass criteria (spec section 5): on 3 cold, high-bitrate videos "BTR mode beats direct mode on time to first frame and seek-to-resume, with no more stalls", and BTR "feels at least as good as the official app". Also: you can log in and play a 4K HDR video you have access to.

Mode order and seek positions per video (the seek percentages are where you drag to):

- Video 1: BTR first (seeks at 30%, 50%, 70%), then direct (40%, 60%, 80%).
- Video 2: direct first (seeks at 30%, 50%, 70%), then BTR (40%, 60%, 80%).
- Video 3: BTR first (seeks at 30%, 50%, 70%), then direct (40%, 60%, 80%).

| video | run | mode | 编码 picked | codec shown | 首帧 | seek 1 跳转恢复 | seek 2 | seek 3 | 卡顿 after 2 min | 画质 shown |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 1 | 1st | BTR | | | | | | | | |
| 1 | 2nd | direct | | | | | | | | |
| 1 | extra | BTR | HEVC | | | | n/a | n/a | | |
| 2 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 2 | 1st | direct | | | | | | | | |
| 2 | 2nd | BTR | | | | | | | | |
| 3 | official app | official app | n/a | n/a | | one seek: | n/a | n/a | n/a | n/a |
| 3 | 1st | BTR | | | | | | | | |
| 3 | 2nd | direct | | | | | | | | |

For the official app rows, write the stopwatch time for first frame and for one seek. If you only timed video 1, leave the other official app rows empty.

## Also check

1. Stats box in landscape full screen: rotate and go full screen. The stats box sits in the top-left corner and does not cover the player's buttons.
2. 清晰度 picker: the value shown matches the 画质 line in the stats box (for example 1080P 高码率), not a higher quality than what is playing.
3. Dolby Vision: if your account has a Dolby Vision video, open it. Note whether it plays or the pill shows 直连（回退）.
4. Wi-Fi to cellular: while a video plays, turn Wi-Fi off in Control Center. Playback keeps going (a short pause is fine; it must not stay stuck or show 播放失败).
5. Background then BTR: with BTR 加速 on, leave BiliFast in the background for a few minutes, come back, open a different video. The pill and 模式 line must say BTR, not 直连.
6. Account row: if you ever see 登录已过期，重新登录 or 无法获取账号信息，点按重试, tap it. Retry should clear the message, or login should bring back your name. Tell Claude if it doesn't.
7. Picture in picture (swipe home while playing), lock screen controls (play/pause, seek), and rotating to landscape and back. Playback must continue each time.

## Troubleshooting

- **Nothing on the PC:** check the phone is on the same Wi-Fi as the PC (not cellular, not a guest network). Check that Windows did not block Python (Windows Defender Firewall → allow Python on private networks). Then try typing `192.168.50.201:47321` by hand.
- **视频服务器暂时无法访问:** tap 重试 once or twice. If it keeps happening, tell Claude which video it was.
- **Every video shows 直连（回退）:** tell Claude. The logs on the PC show why BTR was dropped.

## When done

Tell Claude. The logs are already on the PC under `logs/<date>/`, so you don't need to send anything.
