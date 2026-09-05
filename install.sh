#!/bin/bash
# PairHop's version-pinned installer. No sudo, package manager, or build tools required.
set -euo pipefail

main() {
    local version='0.1.2'
    local expected_sha256='0fdbb14319ef8b6991d80ce2336a93a1df7e45f0c09f90d1a0514d6347c0cbbb'
    local asset="pairhop-v${version}-macos-arm64"
    local url="https://github.com/zzzZZZ-JW/pairhop/releases/download/v${version}/${asset}"
    local signature='=anchor apple generic and identifier "com.zhangjiawei.chrome-icloud-pairing" and certificate leaf[subject.OU] = "R9PVW8HZY2"'
    local binary actual_sha256

    [[ "$(/usr/bin/uname -s)" == Darwin ]] || { echo 'PairHop requires macOS.' >&2; return 1; }
    [[ "$(/usr/bin/uname -m)" == arm64 ]] || { echo 'This release requires Apple Silicon and a native arm64 terminal.' >&2; return 1; }
    [[ "${EUID}" != 0 ]] || { echo 'Run as your normal Mac user, without sudo.' >&2; return 1; }
    [[ "$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)" -ge 14 ]] || { echo 'PairHop requires macOS 14 or newer.' >&2; return 1; }

    umask 077
    PAIRHOP_INSTALL_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/pairhop-install.XXXXXXXX")"
    # Use a function instead of interpolating a path into shell code.
    cleanup() { /bin/rm -rf -- "$PAIRHOP_INSTALL_TEMP"; }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    binary="$PAIRHOP_INSTALL_TEMP/pairing-helper"
    /usr/bin/curl --proto '=https' --tlsv1.2 --fail --location --show-error \
        --connect-timeout 15 --max-time 180 --output "$binary" "$url"
    actual_sha256="$(/usr/bin/shasum -a 256 "$binary" | /usr/bin/awk '{print $1}')"
    [[ "$actual_sha256" == "$expected_sha256" ]] || { echo 'SHA-256 mismatch; nothing installed.' >&2; return 1; }
    /usr/bin/codesign --verify --strict --verbose=2 -R "$signature" "$binary"
    /bin/chmod 700 "$binary"
    "$binary" install
    printf '\nPairHop is installed. For this terminal session:\n  export PATH="$HOME/.local/bin:$PATH"\n  pairhop status\n\nFirst run: grant Accessibility to pairing-helper in System Settings.\n'
    cleanup
    trap - EXIT INT TERM
}

main "$@"
