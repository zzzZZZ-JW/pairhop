# PairHop

**A small bridge from Apple's pairing code to Chrome's official iCloud Passwords extension.**

[中文](../README.md) · [License](../LICENSE) · [Security model](../SECURITY.md)

Click “Enable Password AutoFill” in Chrome. PairHop reads the six-digit code from Apple's native dialog, types it into the official extension and checks for positive connection evidence. Password access and Touch ID remain Apple's responsibility.

A native Swift executable plus a per-user LaunchAgent: no `.app`, menu bar, Dock icon or settings window. It waits for system events, with no repeating idle scan, and performs bounded work when a pairing request appears. No OCR, clipboard use, network access during operation, or stored codes.

## Install and use

Stable **v0.1.2** fixes missed pairing triggers after Chrome restarts and window reopening. See the [stability investigation and manual validation](stability-fix.md).

Stable v0.1.2 provides an Apple Silicon binary for macOS 14+ (the API deployment target). Actual device validation is limited to macOS 27 Beta, Chrome 152 and Apple's extension 3.3.0. It is Developer ID signed with Hardened Runtime, **not notarized**.

Install Apple's [official extension](https://chromewebstore.google.com/detail/icloud-passwords/pejdijmoenmkgeppbflobdenhhabjlaj), then run in a native arm64 terminal, without sudo:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/zzzZZZ-JW/pairhop/v0.1.2/install.sh | /bin/bash
export PATH="$HOME/.local/bin:$PATH"
pairhop status
```

The installer verifies a pinned SHA-256 and publisher signature. Initial macOS authorization still requires opening System Settings → Privacy & Security → Accessibility and enabling **pairing-helper** at:

```text
~/Library/Application Support/ChromeICloudPairingHelper/pairing-helper
```

Then run `pairhop stop && pairhop start && pairhop status`. Accessibility and input authorization should both be true. Add the PATH export to your shell profile if desired, or use `"$HOME/.local/bin/pairhop"` directly.

| Command | Effect |
|---|---|
| `pairhop status` | Process, permission and last-result snapshot |
| `pairhop stop` | Stop and disable login startup |
| `pairhop start` | Resume and enable login startup |
| `pairhop install --diagnostic` | Observe without typing |
| `pairhop install` | Install / return to automatic mode |
| `pairhop uninstall` | Remove this tool, its managed link, startup config and records |

Normal operation requires no terminal. After an aborted attempt, close the current pairing dialog and trigger a new one. PairHop never clears existing manual input or forces application focus.

## Evidence and limits

The original 30-cycle test used a UI automation tool that accessed Chrome's accessibility tree. Later user testing exposed missed triggers that those accesses masked. These samples measure performance with the tool present; they do not establish unattended restart reliability. Closing every window while leaving Chrome running is also a separate lifecycle scenario.

The v0.1.0 engine baseline completed 30/30 independent Chrome restart/pairing cycles on one Mac. Ready-to-input P95 was 155.9 ms; observed-request-to-confirmation P95 was 646.1 ms. The 15-minute AC idle run with Chrome closed averaged approximately 0.000181% of one logical CPU and about 6 MiB physical footprint. These are bounded observations, not universal guarantees or whole-device watt measurements.

v0.1.1 adds CLI link management and distribution; the pairing engine source is unchanged. The baseline is **not a rerun on the v0.1.1 binary**. See [measurement details and open validation items](performance.md).

Runtime signature, exact extension origin, unique-window and per-digit focus/progress checks reduce accidental input. Accessibility reads and event posting are not atomic. Other locales, input methods, permission revocation, sleep/login, concurrent requests, battery/Low Power Mode and long-duration stability still need live validation. There are no Gatekeeper bypass instructions.

## Build

With Swift 6+ on macOS:

```sh
git clone https://github.com/zzzZZZ-JW/pairhop.git
cd pairhop
./scripts/test.sh
./scripts/build.sh
"$(swift build -c release --show-bin-path)/pairing-helper" install
```

The default local signature is ad hoc. Set `PAIRHOP_SIGNING_IDENTITY` for a stable identity; changing identity or installation path may require new Accessibility authorization. See [Contributing](../CONTRIBUTING.md).

Created and maintained by **[zzzZZZ](https://github.com/zzzZZZ-JW)**. MIT licensed. Independent from Apple and Google.
