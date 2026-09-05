import AppKit
import ApplicationServices
import Security
import PairingCore

enum AX {
    static func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v
    }
    static func string(_ e: AXUIElement, _ name: String) -> String {
        guard let v = value(e, name) else { return "" }
        if let s = v as? String { return s }
        if CFGetTypeID(v) == CFURLGetTypeID() { return (v as! URL).absoluteString }
        return ""
    }
    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(e, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func children(_ e: AXUIElement, _ name: String = kAXChildrenAttribute) -> [AXUIElement] {
        guard let a = value(e, name) as? [AnyObject] else { return [] }
        return a.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }
    static func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) }
    static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        guard let a, let b else { return false }; return CFEqual(a, b)
    }
    /// Bounded traversal, scoped to a known window/document. Never traverses unrelated HTML documents.
    static func walk(_ root: AXUIElement, limit: Int = 100, depth: Int = 12, skipWeb: Bool = false,
                     _ visit: (AXUIElement) -> Bool) -> [AXUIElement] {
        var stack: [(AXUIElement, Int)] = [(root, 0)], result: [AXUIElement] = []; var seen = 0
        while let (e,d) = stack.popLast(), seen < limit {
            seen += 1
            if visit(e) { result.append(e); continue }
            if d >= depth || (skipWeb && role(e) == "AXWebArea") { continue }
            for c in children(e).reversed() { stack.append((c,d+1)) }
        }
        return result
    }
}

struct TrustedProcess {
    let app: NSRunningApplication
    let ax: AXUIElement
    let kind: String
    static func create(_ app: NSRunningApplication) -> TrustedProcess? {
        let kind: String, requirement: String
        switch app.bundleIdentifier {
        case "com.google.Chrome":
            kind = "chrome"
            requirement = "anchor apple generic and identifier \"com.google.Chrome\" and certificate leaf[subject.OU] = \"EQHXZ8M8AV\""
        case "com.apple.PasswordManagerBrowserExtensionHelper":
            kind = "helper"
            requirement = "anchor apple and identifier \"com.apple.PasswordManagerBrowserExtensionHelper\""
        default: return nil
        }
        var code: SecCode?, req: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: app.processIdentifier] as CFDictionary, [], &code) == errSecSuccess,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess,
              let code, let req, SecCodeCheckValidity(code, [], req) == errSecSuccess else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.15)
        return TrustedProcess(app: app, ax: ax, kind: kind)
    }
}

struct PinWindow {
    let process: TrustedProcess
    let window: AXUIElement
    let text: AXUIElement
    let pin: String
}
struct Popup {
    let process: TrustedProcess
    let window: AXUIElement
    let document: AXUIElement
    let fields: [AXUIElement]
    var values: [String]? {
        let values = fields.compactMap { AX.value($0, kAXValueAttribute) as? String }
        return values.count == fields.count ? values : nil
    }
}

enum Discovery {
    static func pinWindows(_ helper: TrustedProcess) -> [PinWindow] {
        AX.children(helper.ax, kAXWindowsAttribute).compactMap { window in
            let nodes = AX.walk(window, limit: 60, depth: 7) { AX.role($0) == kAXStaticTextRole }
            let text = nodes.map { AX.string($0, kAXValueAttribute) + " " + AX.string($0, kAXTitleAttribute) }.joined(separator: " ")
            // Chrome-specific source text: do not accept an Edge/Firefox pairing request.
            guard text.contains("Chrome"), text.contains("验证码") || text.lowercased().contains("code") else { return nil }
            let pins = nodes.compactMap { node -> (AXUIElement, String)? in
                for key in [kAXValueAttribute, kAXTitleAttribute] {
                    if let pin = PairingRules.pin(from: AX.string(node, key)) { return (node,pin) }
                }
                return nil
            }
            guard pins.count == 1 else { return nil }
            return PinWindow(process: helper, window: window, text: pins[0].0, pin: pins[0].1)
        }
    }
    static func popups(_ chrome: TrustedProcess) -> [Popup] {
        var result: [Popup] = []
        for window in AX.children(chrome.ax, kAXWindowsAttribute) {
            let docs = AX.walk(window, limit: 160, skipWeb: true) {
                AX.role($0) == "AXWebArea" && PairingRules.isPopupURL(AX.string($0,kAXURLAttribute))
            }
            for doc in docs {
                // Chrome exposes the same popup below both its owner window and a floating window.
                // Dedupe by AX identity, never by URL alone (different requests can share the URL).
                if result.contains(where: { AX.same($0.document,doc) }) { continue }
                let fields = AX.walk(doc, limit: 70, depth: 10) { AX.role($0) == kAXTextFieldRole }
                let owner = AX.element(doc,kAXWindowAttribute) ?? window
                result.append(Popup(process: chrome, window: owner, document: doc, fields: fields))
            }
        }
        return result
    }
    static func focused(_ chrome: TrustedProcess) -> AXUIElement? { AX.element(chrome.ax,kAXFocusedUIElementAttribute) }
}
