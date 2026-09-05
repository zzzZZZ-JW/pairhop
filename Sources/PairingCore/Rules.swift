import Foundation

public enum PairingRules {
    public static let extensionID = "pejdijmoenmkgeppbflobdenhhabjlaj"
    public static func pin(from text: String) -> String? {
        let separators = CharacterSet(charactersIn: " \t\r\n\u{00a0}\u{202f}\u{2009}")
        let scalars = text.unicodeScalars.filter { !separators.contains($0) }
        guard scalars.count == 6, scalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }
    public static func isPopupURL(_ text: String) -> Bool {
        guard let u = URLComponents(string: text) else { return false }
        return u.scheme == "chrome-extension" && u.host == extensionID && u.path == "/page_popup.html"
            && u.user == nil && u.password == nil && u.port == nil
    }
    public static func isCompletionURL(_ text: String) -> Bool {
        guard let u = URLComponents(string: text) else { return false }
        return u.scheme == "chrome-extension" && u.host == extensionID && u.path == "/completion_list.html"
            && u.user == nil && u.password == nil && u.port == nil
    }
    public static func isExpectedProgress(values: [String], pin: String, entered: Int) -> Bool {
        guard values.count == 6, pin.count == 6, (0...6).contains(entered) else { return false }
        let digits = pin.map(String.init)
        return values.enumerated().allSatisfy { $0.element == ($0.offset < entered ? digits[$0.offset] : "") }
    }
}

/// No raw PIN, page text, account name or website URL belongs in this type.
public struct AttemptRecord: Codable {
    public let id: String
    public let timestamp: Date
    public let outcome: String
    public let readyToInputMS: Double?
    public let observedToInputMS: Double?
    public let observedToConfirmedMS: Double?
    public let enteredDigits: Int
    public let reason: String?
    public init(id: String, outcome: String, readyToInputMS: Double?, observedToInputMS: Double?,
                observedToConfirmedMS: Double?, enteredDigits: Int, reason: String?) {
        self.id = id; self.timestamp = Date(); self.outcome = outcome
        self.readyToInputMS = readyToInputMS; self.observedToInputMS = observedToInputMS
        self.observedToConfirmedMS = observedToConfirmedMS; self.enteredDigits = enteredDigits; self.reason = reason
    }
}
