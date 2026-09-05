#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
# Override DEVELOPER_DIR if your Swift 6+ toolchain is not the selected Xcode.
# Use a stable signing identity for persistent Accessibility permission.
SIGNING_IDENTITY="${PAIRHOP_SIGNING_IDENTITY:--}"
SCRATCH="${PAIRHOP_BUILD_DIR:-$PROJECT/.build}"
/usr/bin/xcrun swift build --package-path "$PROJECT" --scratch-path "$SCRATCH" -c release
BIN="$(/usr/bin/xcrun swift build --package-path "$PROJECT" --scratch-path "$SCRATCH" -c release --show-bin-path)/pairing-helper"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
    /usr/bin/codesign --force --options runtime --identifier com.zhangjiawei.chrome-icloud-pairing --sign - "$BIN"
else
    /usr/bin/codesign --force --options runtime --timestamp --identifier com.zhangjiawei.chrome-icloud-pairing --sign "$SIGNING_IDENTITY" "$BIN"
fi
/usr/bin/codesign --verify --strict "$BIN"
printf '\nBuilt: %s\nInstall: "%s" install\n' "$BIN" "$BIN"
