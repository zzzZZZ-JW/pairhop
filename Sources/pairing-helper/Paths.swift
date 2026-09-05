import Foundation
import OSLog
import MachO
import PairingCore

enum Config {
    static let label = "com.zhangjiawei.chrome-icloud-pairing"
    static let version = "0.1.1"
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChromeICloudPairingHelper")
    static let executable = root.appendingPathComponent("pairing-helper")
    static let commandLink = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/pairhop")
    static let managedCommand = ManagedCommandLink(url: commandLink, target: executable)
    static let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    static let state = root.appendingPathComponent("state.json")
    static let attempts = root.appendingPathComponent("attempts.jsonl")
    static let logger = Logger(subsystem: label, category: "lifecycle")
    static let service = "gui/\(getuid())/\(label)"
    static var json: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e }
}

/// Resolve the running image even when invoked through PATH or the pairhop symlink.
func runningExecutable() throws -> URL {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { throw ToolError("Cannot resolve executable path") }
    return URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.resolvingSymlinksInPath()
}

func atomicWrite<T: Encodable>(_ value: T, to url: URL) throws {
    let data = try Config.json.encode(value)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}

@discardableResult
func command(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    if !allowFailure && p.terminationStatus != 0 { throw ToolError("\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(p.terminationStatus)): \(text)") }
    return text
}
