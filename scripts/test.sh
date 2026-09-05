#!/bin/bash
set -euo pipefail
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/pairhop-tests.XXXXXXXX")"
trap '/bin/rm -rf -- "$SCRATCH"' EXIT
/usr/bin/xcrun swift test --package-path "$PROJECT" --scratch-path "$SCRATCH"
for script in "$PROJECT/install.sh" "$PROJECT/scripts/build.sh" "$PROJECT/scripts/test.sh"; do
    /bin/bash -n "$script"
done
