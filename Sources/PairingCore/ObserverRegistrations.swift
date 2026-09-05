import ApplicationServices

/// A failed AX IPC at launch is retryable, not an unsupported notification.
public struct ObserverRegistrations {
    private let names: [String]
    private var results: [String: AXError] = [:]

    public init(names: [String]) { self.names = names }
    public var registered: Int { results.values.filter { $0 == .success || $0 == .notificationAlreadyRegistered }.count }
    public var unsupported: Int { results.values.filter { $0 == .notificationUnsupported }.count }
    public var pending: Int { names.count - registered - unsupported }
    public var failures: [String: Int32] {
        results.filter { !Self.isSettled($0.value) }.mapValues(\.rawValue)
    }

    public mutating func retry(using register: (String) -> AXError) {
        for name in names where results[name].map(Self.isSettled) != true {
            results[name] = register(name)
        }
    }

    private static func isSettled(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered || result == .notificationUnsupported
    }
}
