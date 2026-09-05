# Contributing

PairHop is maintained by **zzzZZZ** and licensed under MIT. Contributions through issues and pull requests are welcome. Keep the project a native executable with command-line management.

## Build and test

Use macOS with Swift 6+. `./scripts/test.sh` uses a temporary build directory for XCTest to avoid extended-attribute signing problems that can occur in synced Documents directories. `./scripts/build.sh` makes a release binary and signs it locally; it does not install or restart the service.

Optional environment variables:

- `DEVELOPER_DIR`: a compatible Xcode developer directory.
- `PAIRHOP_BUILD_DIR`: build output directory (defaults to `.build`).
- `PAIRHOP_SIGNING_IDENTITY`: your signing identity name or SHA-1 (defaults to ad hoc).

Never commit certificates, private keys, provisioning data, local status files, AX snapshots, codes, personal paths or Instruments recordings.

## Source map

- `Sources/PairingCore/Rules.swift`: code normalization, exact extension URL checks and expected progress.
- `Sources/pairing-helper/Accessibility.swift`: bounded AX access, native-process signature checks and popup discovery.
- `Service.swift`: process/window observers, lifecycle, state snapshots.
- `Pairing.swift`: bounded attempt state, guarded PID-directed input and positive connection evidence.
- `Paths.swift` / `main.swift`: CLI installation, launchd management and command link ownership.

The command-line management path can launch system tools. The active pairing path must not spawn shell commands, access the network, synchronously write records, scan unrelated web content, or maintain a repeating idle timer. Do not weaken origin, signature, uniqueness or focus checks for speed.

## Validation

CI builds, tests parsing/origin/progress rules, verifies the ad-hoc signature and exercises non-installing CLI commands on a hosted macOS runner. Hosted runners cannot prove real Apple iCloud pairing, Accessibility permission continuity, power consumption or login behavior. Changes to pairing logic require a separately recorded live-device test with the exact binary hash.

The published baseline and its limitations are in `docs/performance.md`. Keep measurements tied to their binary, tool versions, supply mode and sampling method. Never include PINs or saved passwords in fixtures or evidence; use synthetic digits in unit tests.

## Releases

Build on a trusted Mac with the maintainer's Developer ID identity. Verify signature and architecture; copy the binary to `pairhop-vVERSION-macos-arm64`, compute SHA-256, and update the installer version/hash before tagging. Publish that binary and `SHA256SUMS.txt` as release assets. The installer must not use an unpinned latest-release URL. Signing credentials are not part of CI or the repository. Notarization, when added, must be explicitly verified rather than inferred from a successful signature.
