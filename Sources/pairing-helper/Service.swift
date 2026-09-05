import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import PairingCore

struct Snapshot: Codable {
    var version = Config.version
    var pid = getpid()
    var updatedAt = Date()
    var startedAt = Date()
    var state = "starting"
    var accessibilityAuthorized = false
    var inputAuthorized = false
    var chromeProcesses = 0
    var helperProcesses = 0
    var observerRegistrations = 0
    var unsupportedRegistrations = 0
    var sourceWindows: Int?
    var targetWindows: Int?
    var targetFieldCounts: [Int]?
    var focusedFieldIndex: Int?
    var lastAttempt: AttemptRecord?
    var attemptsCompleted = 0
    var relevantEvents = 0
    var eventCounts: [String:Int] = [:]
    var lastInspection: String?
    var lastSkipReason: String?
    var automaticInputEnabled = false
}

final class Observation {
    let process: TrustedProcess
    let observer: AXObserver
    let source: CFRunLoopSource
    var registered = 0
    var unsupported = 0
    init?(_ process: TrustedProcess, service: PairingService) {
        self.process = process
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, context in
            guard let context else { return }
            let service = Unmanaged<PairingService>.fromOpaque(context).takeUnretainedValue()
            service.event(element: element, notification: notification as String)
        }
        guard AXObserverCreate(process.app.processIdentifier, callback, &observer) == .success, let observer else { return nil }
        self.observer = observer; self.source = AXObserverGetRunLoopSource(observer)
        var names = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
        if process.kind == "chrome" { names.append(kAXFocusedUIElementChangedNotification) }
        for name in names {
            let r = AXObserverAddNotification(observer, process.ax, name as CFString, Unmanaged.passUnretained(service).toOpaque())
            if r == .success { registered += 1 } else { unsupported += 1 }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    deinit { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
}

/// All mutable engine state and AX calls are serialized on this queue.
/// Main run loop only receives system callbacks. No repeating timer exists.
final class PairingService {
    let work = DispatchQueue(label: "pairing.active", qos: .utility)
    let disk = DispatchQueue(label: "pairing.records", qos: .utility)
    var state = Snapshot()
    var observations: [pid_t: Observation] = [:]
    var workspaceTokens: [NSObjectProtocol] = []
    var signals: [DispatchSourceSignal] = []
    var queued = false
    let automatic: Bool
    var stopped = false
    var active: Attempt?
    var handledWindows: [AXUIElement] = []
    var pendingSince: Double?
    let keySource = CGEventSource(stateID: .privateState)
    init(automatic: Bool) { self.automatic = automatic; state.automaticInputEnabled = automatic }

    func run() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                self?.work.async { [weak self] in
                    guard let self else { return }
                    if n.name == NSWorkspace.didLaunchApplicationNotification || n.name == NSWorkspace.didTerminateApplicationNotification {
                        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              ["com.google.Chrome", "com.apple.PasswordManagerBrowserExtensionHelper"].contains(app.bundleIdentifier ?? "") else { return }
                    }
                    if let a = self.active,
                       NSWorkspace.shared.frontmostApplication?.processIdentifier != a.target.process.app.processIdentifier {
                        self.finish(a,"aborted",reason:"foreground_changed")
                    }
                    if n.name == NSWorkspace.didActivateApplicationNotification, self.state.accessibilityAuthorized {
                        return
                    }
                    self.refreshProcesses()
                    if n.name != NSWorkspace.didActivateApplicationNotification { self.scheduleInspection() }
                }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.work.async {
                    guard let self else { return }
                    if let a = self.active { self.finish(a,"aborted",reason:"session_suspended") }
                    self.pendingSince = nil; self.state.state = "suspended"; self.save()
                }
            })
        }
        for number in [SIGTERM, SIGINT, SIGUSR1] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: work)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if number == SIGUSR1 { self.refreshProcesses(); self.diagnose(); return }
                self.stopped = true
                if let a = self.active { self.finish(a,"aborted",reason:"service_stopped") }
                self.observations.removeAll(); self.state.state = "stopped"; self.save()
                self.disk.async { exit(0) }
            }
            source.resume(); signals.append(source)
        }
        work.async {
            // Prompt once from the actual launchd-owned process, never from a transient CLI client.
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            self.refreshProcesses(); self.diagnose(); self.scheduleInspection()
            Config.logger.info("Started version \(Config.version, privacy: .public)")
        }
        RunLoop.main.run()
    }

    func refreshProcesses() {
        let trusted = AXIsProcessTrusted()
        let input = CGPreflightPostEventAccess()
        let before = "\(state.accessibilityAuthorized)/\(state.inputAuthorized)/\(observations.keys.sorted())/\(state.state)"
        state.accessibilityAuthorized = trusted; state.inputAuthorized = input
        guard trusted else {
            observations.removeAll(); state.state = "needs_accessibility_permission"
            if !before.hasSuffix("/needs_accessibility_permission") { save() }
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.google.Chrome" || $0.bundleIdentifier == "com.apple.PasswordManagerBrowserExtensionHelper"
        }
        let live = Set(apps.map(\.processIdentifier))
        for pid in Array(observations.keys) {
            if !live.contains(pid) || observations[pid]?.process.app.isTerminated == true
                || observations[pid]?.process.app.launchDate != apps.first(where: { $0.processIdentifier == pid })?.launchDate {
                observations.removeValue(forKey: pid)
            }
        }
        for app in apps where observations[app.processIdentifier] == nil {
            if let process = TrustedProcess.create(app), let watcher = Observation(process, service: self) {
                observations[app.processIdentifier] = watcher
            }
        }
        state.chromeProcesses = observations.values.filter { $0.process.kind == "chrome" }.count
        state.helperProcesses = observations.values.filter { $0.process.kind == "helper" }.count
        state.observerRegistrations = observations.values.reduce(0) { $0 + $1.registered }
        state.unsupportedRegistrations = observations.values.reduce(0) { $0 + $1.unsupported }
        if active == nil { state.state = input ? (automatic ? "ready" : "diagnostic_only") : "needs_input_permission" }
        let after = "\(trusted)/\(input)/\(observations.keys.sorted())/\(state.state)"
        if before != after { save() }
    }

    func event(element: AXUIElement, notification: String) {
        work.async(qos: .userInitiated) {
            guard !self.stopped, self.state.state != "suspended" else { return }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element,&pid) == .success,
                  let process = self.observations[pid]?.process else { return }
            self.state.eventCounts[process.kind + "/" + notification, default:0] += 1
            if notification == kAXFocusedUIElementChangedNotification {
                // Cheap ancestor walk: normal website fields never cause a browser-wide scan.
                // Chrome can send this notification on its application element.
                var node = Discovery.focused(process); var popup = false
                for _ in 0..<12 {
                    guard let n = node else { break }
                    if AX.role(n) == "AXWebArea" {
                        popup = PairingRules.isPopupURL(AX.string(n,kAXURLAttribute)); break
                    }
                    node = AX.element(n,kAXParentAttribute)
                }
                guard popup else { return }
            }
            if process.kind == "helper", self.active == nil, self.pendingSince == nil {
                // This signed system helper's window event may precede its AX text.
                self.pendingSince = monotonic()
            }
            self.state.relevantEvents += 1
            self.scheduleInspection()
        }
    }
    func scheduleInspection() {
        guard !queued else { return }; queued = true
        work.asyncAfter(deadline: .now() + .milliseconds(5), qos: .userInitiated) {
            self.queued = false
            if self.automatic { self.inspect() } else { self.diagnose() }
        }
    }
    func processes(_ kind: String) -> [TrustedProcess] { observations.values.map(\.process).filter { $0.kind == kind } }
    func diagnose() {
        guard state.accessibilityAuthorized else { save(); return }
        let pins = processes("helper").flatMap(Discovery.pinWindows)
        let popups = processes("chrome").flatMap(Discovery.popups)
        state.sourceWindows = pins.count; state.targetWindows = popups.count
        state.targetFieldCounts = popups.map { $0.fields.count }
        state.focusedFieldIndex = popups.first.flatMap { popup in
            popup.fields.firstIndex { AX.same($0,Discovery.focused(popup.process)) }
        }
        save()
    }
    func save() {
        state.updatedAt = Date(); let snapshot = state
        disk.async {
            do { try atomicWrite(snapshot, to: Config.state) }
            catch { Config.logger.error("State write failed") }
        }
    }
}
