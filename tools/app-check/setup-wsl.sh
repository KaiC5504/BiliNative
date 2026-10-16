#!/usr/bin/env bash
# One-time setup for tools/check-app.sh, run inside WSL Ubuntu:
#   bash tools/app-check/setup-wsl.sh /mnt/d/Tools/Xcode/Xcode_27.1.xip
# Installs Swift (swiftly), xtool (unpacked, no FUSE) and the Darwin SDK built from the xip.
set -euo pipefail

SWIFT_VERSION=6.4.1
XTOOL_VERSION=1.22.2
xip=${1:?usage: setup-wsl.sh /path/to/Xcode.xip}

if [ ! -x "$HOME/.local/share/swiftly/bin/swiftly" ]; then
    tmp=$(mktemp -d)
    curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz" | tar zx -C "$tmp"
    "$tmp/swiftly" init --quiet-shell-followup --assume-yes --skip-install
    rm -rf "$tmp"
fi
# shellcheck disable=SC1091
. "$HOME/.local/share/swiftly/env.sh"
swiftly install "$SWIFT_VERSION" --use --assume-yes --post-install-file /tmp/swift-deps.sh
if [ -s /tmp/swift-deps.sh ]; then
    # Swift's system libraries; from Windows without a sudo password:
    #   wsl -d Ubuntu -u root -- bash /tmp/swift-deps.sh
    sudo bash /tmp/swift-deps.sh
fi
command -v rsync >/dev/null || sudo apt-get -y install rsync

# The AppImage needs FUSE, which hangs xtool's XIP extraction on WSL2 (xtool-org/xtool#316).
mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
rm -rf "$HOME/.local/opt/xtool" "$HOME/.local/opt/squashfs-root"
curl -fsSL -o "$HOME/.local/opt/xtool.AppImage" \
    "https://github.com/xtool-org/xtool/releases/download/$XTOOL_VERSION/xtool-$(uname -m).AppImage"
chmod +x "$HOME/.local/opt/xtool.AppImage"
(cd "$HOME/.local/opt" && ./xtool.AppImage --appimage-extract >/dev/null && mv squashfs-root xtool)
rm "$HOME/.local/opt/xtool.AppImage"
ln -sf "$HOME/.local/opt/xtool/AppRun" "$HOME/.local/bin/xtool"

# Builds the SDK straight from the xip; no Apple ID login needed for compiling.
"$HOME/.local/bin/xtool" sdk install --slim "$xip"
"$HOME/.local/bin/xtool" sdk status
