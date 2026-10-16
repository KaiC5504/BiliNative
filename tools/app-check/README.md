# Local compile check (xtool)

`tools/check-app.sh` compiles the `BiliNative` app target and `AppTests` for iOS on the Windows PC, in
WSL Ubuntu, using the iOS SDK that [xtool](https://github.com/xtool-org/xtool) builds from an Xcode
download. It takes about 35 s from cold and a few seconds after small edits, instead of a 12-16 minute
CI round.

`Package.swift` here mirrors the two targets in `ios/project.yml` for SwiftPM (Debug defines `DEBUG` and
`DEV_TOOLS`, Release only `DEV_TOOLS`, Swift 5 mode, iOS 26.0). If a target, define or dependency changes
in `project.yml`, change it here too. CI and TestFlight never read this folder.

## What it does not cover

- Running tests, the simulator, screenshots, launching the app: CI only.
- Asset catalogs, `Localizable.xcstrings`, Info.plist, signing, entitlements: not built at all.
- The SDK and compiler differ from CI's: Xcode 27.1 (iOS 27 SDK, Swift 6.4) here, Xcode 26.6
  (iOS 26.5 SDK, Swift 6.3) on CI until the runner image gets Xcode 27. A clean local run is a strong
  hint, not proof; the CI compile check stays the gate.

## Setup (once per PC)

1. Download Xcode 27 (27.1 on KaiC's PC) with the owner's Apple ID from
   <https://developer.apple.com/download/all/?q=Xcode%2027> into `D:\Tools\Xcode\` (outside the repo;
   never commit it or anything extracted from it).
2. In WSL: `bash tools/app-check/setup-wsl.sh /mnt/d/Tools/Xcode/Xcode_27.1.xip`. It installs Swift 6.4.1
   (swiftly), xtool 1.22.2 and the SDK (`~/.swiftpm/swift-sdks/darwin.artifactbundle`). No Apple ID
   login: compiling needs none.

Builds are staged in `~/.cache/bilinative-check/<checkout>/` inside WSL; delete that folder to start clean.
The full log of the last run is `last-build.log` there.
