# Security model

PairHop is an independent local helper for a user's own Mac. It transfers the six-digit code that Apple's PasswordManagerBrowserExtensionHelper visibly presents to the official iCloud Passwords Chrome extension. It does not bypass the pairing protocol, retrieve saved website passwords, or automate Touch ID.

## Trust checks

- Apple native helper: runtime code signature, Apple anchor, exact bundle identifier.
- Google Chrome: runtime code signature, Apple signing chain, Google's team identifier, exact bundle identifier.
- Destination: `chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/page_popup.html`, exact origin/path, six empty fields, unique source and target, expected foreground application and field focus.
- Every digit: permission, process lifetime, window/source consistency, input progress, focus, modifiers and hardware input counters are checked. Events are addressed to Chrome's PID. Counters are inspected; keystroke contents are not recorded.
- A bounded attempt stops on ambiguity or unexpected input. Each handled source window is suppressed while it remains identifiable. No infinite retry or automatic clearing of fields.

Accessibility reads and event delivery are separate system calls, not an atomic transaction. These checks reduce races; they cannot guarantee zero mistargeted input under every interleaving. A compromised trusted Chrome or Apple process, an attacker controlling the current user, or an extension modified inside a trusted browser is outside this threat model. An Accessibility grant is a powerful OS permission, not a narrowly scoped permission to read one dialog.

## Data and distribution

Codes exist in process memory only and are not written to the clipboard, disk or logs. Swift strings do not provide guaranteed cryptographic memory zeroization. Status and a bounded history contain result categories and timings, not codes, passwords, account names or visited website URLs. Core dumps are disabled for the LaunchAgent. The running helper has no network client and no built-in updater.

The release installer downloads a fixed binary from GitHub, verifies a pinned SHA-256, and checks its signature against an Apple chain, the release team's identity and the program identifier. Source builds may use the builder's own identity. The current preview is Developer ID signed with Hardened Runtime but **not notarized**; cross-machine Gatekeeper behavior has not been validated. No instructions remove quarantine or disable OS protection.

## Reports

For a suspected security defect, use this repository's **Security → Report a vulnerability** private reporting entry. Do not publish codes, passwords, screenshots of sensitive fields or unredacted system logs in a public issue. Ordinary compatibility reports can use Issues with macOS/Chrome/extension versions and a redacted result category.

The preview does not yet have a guaranteed support or disclosure-response schedule.
