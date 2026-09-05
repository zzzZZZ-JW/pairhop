import AppKit
import ApplicationServices
import CoreGraphics
import PairingCore

func monotonic() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000 }

/// Only counters, never key contents. No event tap or idle keyboard listener.
func hardwareInputCounters() -> [UInt32] {
    [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        .map { CGEventSource.counterForEventType(.hidSystemState, eventType: $0) }
}

final class Attempt {
    let id = UUID().uuidString
    let source: PinWindow
    let target: Popup
    let observedAt: Double
    let readyAt = monotonic()
    let hardwareInput = hardwareInputCounters()
    var sent = 0
    var acknowledged = 0
    var lastSentAt = 0.0
    var inputAt: Double?
    var deadline: Double
    init(source: PinWindow, target: Popup, observedAt: Double) {
        self.source = source; self.target = target; self.observedAt = observedAt
        self.deadline = monotonic() + 3
    }
}

extension PairingService {
    func skip(_ source: PinWindow, reason: String) {
        handledWindows.append(source.window); pendingSince = nil
        state.lastSkipReason = reason; save()
    }
    func inspect() {
        guard automatic, active == nil, !stopped, state.state != "suspended",
              state.accessibilityAuthorized, state.inputAuthorized else { return }
        let now = monotonic()
        let targets = processes("chrome").flatMap(Discovery.popups)
        // The native messaging helper may become visible to NSWorkspace only
        // after Chrome's launch notification. Discover it on the actual PIN UI.
        if targets.contains(where: { $0.fields.count == 6 }), processes("helper").isEmpty { refreshProcesses() }
        let sources = processes("helper").flatMap(Discovery.pinWindows)
        state.lastInspection = "sources=\(sources.count) targets=\(targets.count) helperProcesses=\(processes("helper").count)"
        handledWindows.removeAll { handled in !sources.contains { AX.same($0.window,handled) } }
        // AX can announce the popup before Apple's six-digit text has appeared.
        // Retry only while a unique official PIN form is actually present.
        if sources.isEmpty, targets.count == 1, targets[0].fields.count == 6 {
            if pendingSince == nil { pendingSince = now }
            if now - (pendingSince ?? now) < 1.5 { retryDiscovery() }
            return
        }
        guard sources.count == 1, let source = sources.first else {
            if sources.isEmpty, let pendingSince, now - pendingSince < 1.5 { retryDiscovery(); return }
            pendingSince = nil; return
        }
        guard !handledWindows.contains(where: { AX.same($0,source.window) }) else { pendingSince = nil; return }
        guard targets.count <= 1 else { skip(source,reason:"ambiguous_target"); return }
        if pendingSince == nil { pendingSince = now }
        guard let target = targets.first, target.fields.count == 6 else {
            if now - (pendingSince ?? now) < 1.5 { retryDiscovery() }
            else { skip(source,reason:"target_not_ready") }
            return
        }
        guard let initialValues = target.values, initialValues.allSatisfy(\.isEmpty),
              !target.process.app.isTerminated, !source.process.app.isTerminated else {
            skip(source,reason:"nonempty_unreadable_or_terminated"); return
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focus = Discovery.focused(target.process)
        if front != target.process.app.processIdentifier || !AX.same(target.fields.first,focus) {
            // Window creation precedes Chrome focusing digit one. Allow only that
            // bounded transition; never activate an app or move the user's focus.
            let legitimateTransition = (front == target.process.app.processIdentifier || front == source.process.app.processIdentifier)
                && !target.fields.dropFirst().contains(where: { AX.same($0,focus) })
            if legitimateTransition && now - (pendingSince ?? now) < 1.5 { retryDiscovery() }
            else { skip(source,reason:legitimateTransition ? "focus_not_ready" : "user_focus_changed") }
            return
        }
        let attempt = Attempt(source: source, target: target, observedAt: pendingSince ?? now)
        pendingSince = nil; active = attempt
        state.lastSkipReason = nil
        state.state = "pairing"
        Config.logger.info("Pairing request started")
        tick(attempt)
    }

    func retryDiscovery() {
        guard !queued else { return }; queued = true
        work.asyncAfter(deadline: .now() + .milliseconds(20), qos: .userInitiated) {
            self.queued = false; self.inspect()
        }
    }

    func tick(_ a: Attempt) {
        guard active === a else { return }
        let now = monotonic()
        guard !stopped, state.state != "suspended", AXIsProcessTrusted(), CGPreflightPostEventAccess(),
              !a.target.process.app.isTerminated, !a.source.process.app.isTerminated else {
            finish(a,"aborted",reason:"permission_or_process_changed"); return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == a.target.process.app.processIdentifier else {
            finish(a, a.sent == 6 ? "submitted_unconfirmed" : "aborted", reason:"foreground_changed"); return
        }
        guard hardwareInputCounters() == a.hardwareInput else {
            finish(a,a.sent == 6 ? "submitted_unconfirmed" : "aborted",reason:"user_input_detected"); return
        }
        if a.sent == 6 && pairedEvidence(a.target) {
            if a.inputAt == nil { a.inputAt = now }
            finish(a,"confirmed",reason:nil)
            // Dismiss only the Apple source dialog after positive extension evidence.
            let done = AX.walk(a.source.window, limit:30,depth:5) { node in
                AX.role(node) == kAXButtonRole && ["完成","Done"].contains(AX.string(node,kAXTitleAttribute))
            }
            if done.count == 1 { AXUIElementPerformAction(done[0],kAXPressAction as CFString) }
            return
        }
        guard now < a.deadline else {
            finish(a,a.sent == 6 ? "submitted_unconfirmed" : "aborted",reason:"bounded_wait_expired"); return
        }
        guard PairingRules.isPopupURL(AX.string(a.target.document,kAXURLAttribute)),
              AX.children(a.target.process.ax,kAXWindowsAttribute).contains(where: { AX.same($0,a.target.window) }) else {
            finish(a,a.sent == 6 ? "submitted_unconfirmed" : "aborted",reason:"target_closed"); return
        }
        if a.sent == 6 {
            guard let values = a.target.values else { later(a,milliseconds:15); return }
            if PairingRules.isExpectedProgress(values:values,pin:a.source.pin,entered:6), a.inputAt == nil { a.inputAt = now }
            if values.count == 6 && values.contains(where: { !$0.isEmpty }) && !PairingRules.isExpectedProgress(values:values,pin:a.source.pin,entered:6) {
                finish(a,"submitted_unconfirmed",reason:"values_changed_after_submit"); return
            }
            later(a, milliseconds:15); return
        }
        guard AX.children(a.source.process.ax,kAXWindowsAttribute).contains(where: { AX.same($0,a.source.window) }),
              PairingRules.pin(from:AX.string(a.source.text,kAXValueAttribute)) == a.source.pin
                || PairingRules.pin(from:AX.string(a.source.text,kAXTitleAttribute)) == a.source.pin else {
            finish(a,"aborted",reason:"source_changed"); return
        }
        guard let values = a.target.values else {
            finish(a,"aborted",reason:"target_unreadable"); return
        }
        let focus = Discovery.focused(a.target.process)
        if a.sent > a.acknowledged {
            if PairingRules.isExpectedProgress(values:values,pin:a.source.pin,entered:a.sent), AX.same(focus,a.target.fields[a.sent]) {
                a.acknowledged = a.sent
            } else if PairingRules.isExpectedProgress(values:values,pin:a.source.pin,entered:a.acknowledged),
                      AX.same(focus,a.target.fields[a.acknowledged]), now - a.lastSentAt < 0.15 {
                later(a,milliseconds:5); return
            } else {
                finish(a,"aborted",reason:"unexpected_input_or_focus"); return
            }
        }
        guard PairingRules.isExpectedProgress(values:values,pin:a.source.pin,entered:a.sent), AX.same(focus,a.target.fields[a.sent]) else {
            finish(a,"aborted",reason:"unexpected_input_or_focus"); return
        }
        let modifiers = CGEventSource.flagsState(.combinedSessionState)
        guard modifiers.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift]).isEmpty else {
            finish(a,"aborted",reason:"modifier_key_held"); return
        }
        let digits = Array(a.source.pin.utf16)
        let keyCodes: [CGKeyCode] = [29,18,19,20,21,23,22,26,28,25]
        let scalar = digits[a.sent]; let keyCode = keyCodes[Int(scalar - 48)]
        guard let down = CGEvent(keyboardEventSource:keySource,virtualKey:keyCode,keyDown:true),
              let up = CGEvent(keyboardEventSource:keySource,virtualKey:keyCode,keyDown:false) else {
            finish(a,"aborted",reason:"event_creation_failed"); return
        }
        var unit = scalar
        for event in [down,up] {
            event.flags = []
            event.keyboardSetUnicodeString(stringLength:1,unicodeString:&unit)
            event.setIntegerValueField(.keyboardEventAutorepeat,value:0)
            event.setIntegerValueField(.eventSourceUserData,value:0x50414952)
        }
        // Sending to a PID never intentionally redirects text to another foreground app.
        down.postToPid(a.target.process.app.processIdentifier)
        up.postToPid(a.target.process.app.processIdentifier)
        a.sent += 1; a.lastSentAt = monotonic()
        later(a,milliseconds:5)
    }
    func later(_ a: Attempt, milliseconds: Int) {
        work.asyncAfter(deadline:.now() + .milliseconds(milliseconds), qos: .userInitiated) { [weak a] in
            guard let a else { return }; self.tick(a)
        }
    }

    func pairedEvidence(_ target: Popup) -> Bool {
        guard PairingRules.isPopupURL(AX.string(target.document,kAXURLAttribute)) else { return false }
        let fields = AX.walk(target.document,limit:75,depth:10) { AX.role($0) == kAXTextFieldRole }
        guard fields.isEmpty else { return false }
        // These labels are only emitted by the official 3.3.0 popup's SessionKeySet branch.
        let labels: Set<String> = ["你的密码已与 iCloud 钥匙串同步","选取并使用已保存的密码：","正在载入密码…",
            "Your passwords are synced with iCloud Keychain","Choose a saved password to use:","Loading passwords…"]
        return !AX.walk(target.document,limit:75,depth:10, { node in
            AX.role(node) == kAXStaticTextRole && (labels.contains(AX.string(node,kAXValueAttribute)) || labels.contains(AX.string(node,kAXTitleAttribute)))
        }).isEmpty
    }

    func finish(_ a: Attempt, _ outcome: String, reason: String?) {
        guard active === a else { return }
        let now = monotonic()
        let record = AttemptRecord(id:a.id,outcome:outcome,
            readyToInputMS:a.inputAt.map { ($0-a.readyAt)*1000 },
            observedToInputMS:a.inputAt.map { ($0-a.observedAt)*1000 },
            observedToConfirmedMS:outcome == "confirmed" ? (now-a.observedAt)*1000 : nil,
            enteredDigits:a.sent,reason:reason)
        handledWindows.append(a.source.window); active = nil
        state.accessibilityAuthorized = AXIsProcessTrusted()
        state.inputAuthorized = CGPreflightPostEventAccess()
        state.state = !state.accessibilityAuthorized ? "needs_accessibility_permission" : (state.inputAuthorized ? "ready" : "needs_input_permission")
        state.lastAttempt = record; state.attemptsCompleted += 1
        save()
        Config.logger.info("Pairing request ended: \(outcome, privacy:.public)")
        disk.async {
            do {
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
                var lines = (try? String(contentsOf:Config.attempts,encoding:.utf8))?.split(separator:"\n").map(String.init) ?? []
                lines.append(String(decoding:try encoder.encode(record),as:UTF8.self))
                let text = lines.suffix(200).joined(separator:"\n") + "\n"
                try Data(text.utf8).write(to:Config.attempts,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:Config.attempts.path)
            } catch { Config.logger.error("Attempt record write failed") }
        }
    }
}
