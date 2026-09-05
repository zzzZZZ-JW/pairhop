# Changelog

## 0.1.2 — 2026-09-05

First stable release, fixing repeated pairing triggers.

- Initialize native accessibility for every Chrome process through its application role, without relying on an external UI inspector.
- Reconcile Apple's native messaging helper whenever the official six-digit form appears, including when all Chrome windows were closed without quitting Chrome.
- Retry transient observer registration failures during a bounded launch/activation/wake recovery window; expose pending registrations separately from unsupported notifications.
- Rebuild observers after wake and retain the request input guard across suspension.
- Make `status` read-only; keep active listener refresh in `diagnose`.
- Correct the scope of the old automation-assisted stability measurements.

## 0.1.1 — 2026-09-05

First public preview under the **PairHop** name, created and maintained by **zzzZZZ**.

- Version-pinned command-line installer with SHA-256 and publisher signature verification.
- Managed `pairhop` command link with protection for unrelated existing files and symlinks.
- Correct executable resolution when reinstalling through PATH.
- Native Swift background pairing helper, per-user LaunchAgent and command-line lifecycle management.
- Chinese usage guide, English introduction, explicit security model and measured baseline with open validation items.
- MIT license and macOS CI for builds, rules, command-link ownership and installer failure gates.

The pairing engine is unchanged from the locally tested 0.1.0 baseline. The public binary has a different hash and has not repeated the full 30-cycle / 15-minute baseline. Signed, not notarized.

## 0.1.0 — local prototype

Developed the event-driven pairing engine and measured 30 real Chrome restart/pairing cycles plus a 15-minute idle interval. This prototype was not a public GitHub release; only sanitized measurements are included in this repository.
