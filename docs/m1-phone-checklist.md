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

Pick three videos that stutter in the official app (cold, 4K or high bitrate). For each one:

1. In the official app: Share → Copy link.
2. In BiliFast tap 粘贴 (Paste) on the home screen. The player opens and the first frame appears.
3. Check the pill under the video says BTR (pink). The stats box on the video shows 模式, 画质, 首帧, 跳转恢复, 卡顿, 下载.
4. Write down 首帧 and 画质.
5. Seek three times into parts not loaded yet (drag the bar well ahead each time). After each, write down 跳转恢复.
6. Let it play for 2 minutes without touching it. Write down 卡顿 (the 次 count).
7. Scroll the list under the video and turn off BTR 加速. The pill changes to 直连 (blue). Repeat steps 4-6 on the same video.
8. Turn BTR 加速 back on afterwards.
9. In the official app, time the same video with a stopwatch: tap to first frame, and one seek.

## Results

Pass criteria (spec section 5): on 3 cold, high-bitrate videos "BTR mode beats direct mode on time to first frame and seek-to-resume, with no more stalls", and BTR "feels at least as good as the official app". Also: you can log in and play a 4K HDR video you have access to.

| video | mode (BTR / direct / official app) | 首帧 | seek 1 跳转恢复 | seek 2 | seek 3 | 卡顿 after 2 min | 画质 shown |
|---|---|---|---|---|---|---|---|
| 1 | BTR | | | | | | |
| 1 | direct | | | | | | |
| 1 | official app | | | | | n/a | n/a |
| 2 | BTR | | | | | | |
| 2 | direct | | | | | | |
| 2 | official app | | | | | n/a | n/a |
| 3 | BTR | | | | | | |
| 3 | direct | | | | | | |
| 3 | official app | | | | | n/a | n/a |

For the official app rows, write the stopwatch time for first frame and for one seek (seek 1 only).

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
