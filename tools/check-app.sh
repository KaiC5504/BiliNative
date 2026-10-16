#!/usr/bin/env bash
# Compile-checks the iOS app target and its tests on this PC, in WSL, against the iOS SDK that
# xtool extracted from Xcode. Prints compiler errors only. Setup: tools/app-check/README.md.
#
#   bash tools/check-app.sh             Debug, simulator, app + AppTests
#   bash tools/check-app.sh --release   Release (no DEBUG), app only
#   bash tools/check-app.sh --device    build for iPhone instead of the simulator
#   bash tools/check-app.sh --app-only  skip AppTests
#   bash tools/check-app.sh --warnings  print warnings too
#   bash tools/check-app.sh --repo DIR  check another checkout (default: the one holding the current
#                                       folder, else the one holding this script)
set -euo pipefail

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        here=$(cd "$(dirname "$0")" && pwd -W)
        drive=$(printf '%s' "${here:0:1}" | tr '[:upper:]' '[:lower:]')
        MSYS_NO_PATHCONV=1 exec wsl.exe -d Ubuntu --exec bash "/mnt/$drive${here:2}/check-app.sh" "$@"
        ;;
esac

config=debug
triple=arm64-apple-ios-simulator
tests=1
warnings=0
repo=
while [ $# -gt 0 ]; do
    case "$1" in
        --release) config=release; tests=0 ;;
        --device) triple=arm64-apple-ios ;;
        --app-only) tests=0 ;;
        --warnings) warnings=1 ;;
        --repo) repo=${2:?--repo needs a folder}; shift ;;
        --repo=*) repo=${1#--repo=} ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

manifest="$(cd "$(dirname "$0")" && pwd)/app-check/Package.swift"
if [ -n "$repo" ]; then
    case "$repo" in [A-Za-z]:*) repo=$(wslpath -u "$repo") ;; esac
    repo=$(cd "$repo" && pwd)
else
    repo=$PWD
    while [ "$repo" != / ] && [ ! -f "$repo/ios/project.yml" ]; do repo=$(dirname "$repo"); done
    [ -f "$repo/ios/project.yml" ] || repo=$(cd "$(dirname "$0")/.." && pwd)
fi
if [ ! -f "$repo/ios/project.yml" ]; then
    echo "check-app: $repo is not a BiliNative checkout" >&2
    exit 2
fi
sdk="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
[ -n "${XDG_CONFIG_HOME:-}" ] && sdk="$XDG_CONFIG_HOME/swiftpm/swift-sdks/darwin.artifactbundle"
swiftly_bin="$HOME/.local/share/swiftly/bin"
if [ ! -f "$sdk/toolset-swb.json" ] || [ ! -x "$swiftly_bin/swift" ]; then
    echo "check-app: no Swift toolchain or Darwin SDK in WSL. See tools/app-check/README.md." >&2
    exit 3
fi

# WSL's PATH also carries the Windows one, where D:\Tools\Swift would shadow the Linux toolchain.
export PATH="$sdk/toolset/bin:$swiftly_bin:/usr/local/bin:/usr/bin:/bin"
export XCODE_EXTRA_PLATFORM_FOLDERS="$sdk/Developer/Platforms"
unset SDKROOT

# Build on WSL's own disk: reading sources over /mnt/d is slow, and each checkout (worktrees
# included) gets its own folder so incremental builds survive and parallel agents don't collide.
stage="${XDG_CACHE_HOME:-$HOME/.cache}/bilinative-check/$(printf '%s' "$repo" | md5sum | cut -c1-12)"
mkdir -p "$stage"
exec 9>"$stage/.lock"
flock 9

start=$(date +%s)
rsync -a --delete "$repo/ios/Sources/App/" "$stage/App/"
rsync -a --delete "$repo/ios/Tests/AppTests/" "$stage/AppTests/"
rsync -a --delete --exclude .build --exclude .swiftpm "$repo/ios/Packages/BiliCore/" "$stage/BiliCore/"
cp -p "$manifest" "$stage/Package.swift"

build=(swift build --package-path "$stage" --scratch-path "$stage/.build-$config-$triple"
    --build-system swiftbuild --triple "$triple" --toolset "$sdk/toolset-swb.json"
    --configuration "$config" -Xswiftc -diagnostic-style=llvm)
if [ "$tests" = 1 ]; then build+=(--target BiliNativeTests); else build+=(--target BiliNative); fi

log="$stage/last-build.log"
status=0
"${build[@]}" >"$log.raw" 2>&1 || status=$?
# Swift Build colours compiler output even into a file.
sed -e 's/\x1b\[[0-9;]*m//g' "$log.raw" >"$log" && rm "$log.raw"

to_repo() {
    sed -e "s#$stage/App/#ios/Sources/App/#g" \
        -e "s#$stage/AppTests/#ios/Tests/AppTests/#g" \
        -e "s#$stage/BiliCore/#ios/Packages/BiliCore/#g"
}

# The same diagnostic repeats once per compile job that includes the file.
matching() { { grep -E "$1" "$log" || true; } | to_repo | awk '!seen[$0]++'; }

if [ "$warnings" = 1 ]; then matching ': (error|warning): '; else matching ': error: '; fi

errors=$(matching ': error: ' | wc -l)
warns=$(matching ': warning: ' | wc -l)
what="app"
[ "$tests" = 1 ] && what="app + AppTests"
summary="$what, $config, $triple, ${repo##*/}: $errors errors, $warns warnings in $(($(date +%s) - start))s"

if [ "$status" -ne 0 ]; then
    if [ "$errors" -eq 0 ]; then
        echo "check-app: the build failed without a compiler error. Last lines of the log:"
        tail -n 40 "$log" | to_repo
    fi
    echo "FAILED: $summary (full log: $log)"
    exit 1
fi
echo "OK: $summary"
