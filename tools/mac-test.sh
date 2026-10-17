#!/usr/bin/env bash
# Builds and tests this checkout, uncommitted changes included, on KaiC's rented Mac (SSH alias `macrent`
# in ~/.ssh/config). Mirrors the simulator steps of .github/workflows/ios-compile.yml; CI stays the gate
# because the Mac's Xcode can lag the runner's.
#
#   bash tools/mac-test.sh                        build, then run every test
#   bash tools/mac-test.sh --tests A,B/testC      only these (same syntax as the workflow's `tests` input)
#   bash tools/mac-test.sh --build-only           compile app + tests, no run
#   bash tools/mac-test.sh --launch               build, then install and open the app in the simulator
#   bash tools/mac-test.sh --sim "iPhone 17"      another simulator (default: KaiC's iPhone 17 Pro Max)
#   bash tools/mac-test.sh --repo DIR             another checkout (default: the one holding the current folder)
#
# One run at a time: a second session waits for the first. The app builds with nil AppKeys; never copy
# BILI_APP_KEYS, cookies or an Apple ID onto the Mac.
set -euo pipefail

host=macrent
sim="iPhone 17 Pro Max"
mode=test
tests=
repo=
while [ $# -gt 0 ]; do
    case "$1" in
        --tests) tests=$2; shift ;;
        --build-only) mode=build ;;
        --launch) mode=launch ;;
        --sim) sim=$2; shift ;;
        --repo) repo=$2; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
repo=${repo:-$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))}

if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" true 2>/dev/null; then
    echo "The Mac ($host) is not reachable; the rental may have ended. Use CI instead." >&2
    exit 3
fi

echo "Syncing $repo to the Mac..."
git -C "$repo" ls-files -co --exclude-standard -z \
    | grep -zv '^\.claude/' \
    | tar -czf - -C "$repo" --null --ignore-failed-read -T - 2>/dev/null \
    | ssh "$host" 'mkdir -p ~/src && cat > ~/src/stage.tgz'

# ssh joins its arguments into one command line, so they are quoted for the remote shell.
ssh "$host" "bash -s -- $(printf '%q ' "$sim" "$mode" "$tests")" <<'REMOTE'
set -euo pipefail
sim=$1; mode=$2; tests=$3
src=~/src/BiliNative

lock=~/.mac-test.lock
waited=0
until mkdir "$lock" 2>/dev/null; do
    [ $waited -eq 0 ] && echo "The Mac is busy with another run; waiting (remove ~/.mac-test.lock if it is stale)..."
    sleep 10; waited=$((waited + 10))
    if [ $waited -ge 1800 ]; then echo "Still busy after 30 minutes; giving up." >&2; exit 3; fi
done
trap 'rmdir "$lock"' EXIT

rm -rf ~/src/stage && mkdir -p ~/src/stage "$src" ~/logs
tar -xzf ~/src/stage.tgz -C ~/src/stage
rsync -a --delete --exclude /.git/ --exclude /build/ --exclude /ios/BiliNative.xcodeproj/ --exclude /ios/Generated/ \
    ~/src/stage/ "$src/"
cd "$src"
env -u BILI_APP_KEYS python3 tools/write_app_keys.py ios/Generated/AppKeys.swift >/dev/null
(cd ios && ~/tools/xcodegen/bin/xcodegen generate --quiet --use-cache)

udid=$(xcrun simctl list devices available -j | SIM="$sim" python3 -c '
import json, os, sys
best = None
for runtime, items in json.load(sys.stdin)["devices"].items():
    if "iOS" in runtime:
        for device in items:
            if device["name"] == os.environ["SIM"] and device["isAvailable"]:
                best = device["udid"]
print(best or "")
')
if [ -z "$udid" ]; then echo "No simulator named \"$sim\" on the Mac." >&2; exit 2; fi
xcrun simctl boot "$udid" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$udid"

strip_paths() { sed "s#$src/##g"; }
common=(-project ios/BiliNative.xcodeproj -scheme BiliNative -destination "id=$udid" -configuration Debug -derivedDataPath build)

echo "Building on $sim..."
start=$(date +%s)
if ! xcodebuild "${common[@]}" CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    build-for-testing > ~/logs/build.log 2>&1; then
    grep -E "error:" ~/logs/build.log | sort -u | strip_paths | head -40
    echo "BUILD FAILED after $(( $(date +%s) - start )) s (full log: ssh macrent cat ~/logs/build.log)"
    exit 1
fi
echo "Build succeeded in $(( $(date +%s) - start )) s."

case "$mode" in
    build) exit 0 ;;
    launch)
        xcrun simctl install "$udid" build/Build/Products/Debug-iphonesimulator/BiliNative.app
        xcrun simctl launch "$udid" com.kaichuan.bilifast >/dev/null
        echo "BiliFast is open in the $sim simulator on the Mac."
        exit 0 ;;
esac

only=()
if [ -n "$tests" ]; then
    IFS=',' read -ra items <<< "$tests"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)
        [ -n "$item" ] && only+=("-only-testing:BiliNativeTests/$item")
    done
fi
xcrun simctl bootstatus "$udid" -b >/dev/null
media=()
[ -d ~/media ] && media=(TEST_RUNNER_MEDIA_DIR="$HOME/media")

echo "Testing..."
start=$(date +%s)
status=0
# macOS ships bash 3.2, where an empty "${array[@]}" trips set -u.
env ${media[@]+"${media[@]}"} xcodebuild "${common[@]}" ${only[@]+"${only[@]}"} test-without-building > ~/logs/test.log 2>&1 || status=$?
grep -E "error: -\[|: error: |Test skipped" ~/logs/test.log | strip_paths | sort -u | head -40 || true
grep -E "Executed [0-9]+ tests?," ~/logs/test.log | tail -1 | xargs
if [ $status -ne 0 ]; then
    echo "TESTS FAILED after $(( $(date +%s) - start )) s (full log: ssh macrent cat ~/logs/test.log)"
    exit 1
fi
echo "Tests passed in $(( $(date +%s) - start )) s."
REMOTE
