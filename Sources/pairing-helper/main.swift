import Foundation
import Darwin

func launchPID() -> pid_t? {
    let output = (try? command("/bin/launchctl", ["print", Config.service], allowFailure: true)) ?? ""
    for line in output.components(separatedBy: .newlines) {
        let s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("pid = "), let n = Int32(s.dropFirst(6)) { return n }
    }
    return nil
}
func stop() throws {
    try command("/bin/launchctl", ["disable", Config.service])
    try command("/bin/launchctl", ["bootout", Config.service], allowFailure: true)
}
func start() throws {
    guard FileManager.default.fileExists(atPath: Config.plist.path) else { throw ToolError("Not installed. Run install first.") }
    try command("/bin/launchctl", ["enable", Config.service])
    if launchPID() == nil {
        try command("/bin/launchctl", ["bootstrap", "gui/\(getuid())", Config.plist.path], allowFailure: true)
        try command("/bin/launchctl", ["kickstart", Config.service])
    }
}
func install(diagnostic: Bool) throws {
    let fm = FileManager.default
    guard getuid() != 0 else { throw ToolError("Install as your normal Mac user, without sudo.") }
    let source = try runningExecutable()
    try Config.managedCommand.validate()
    try command("/usr/bin/codesign", ["--verify", "--strict", source.path])
    try fm.createDirectory(at: Config.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fm.createDirectory(at: Config.plist.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fm.fileExists(atPath: Config.plist.path) { try stop() }
    if source.path != Config.executable.resolvingSymlinksInPath().path {
        let staged = Config.root.appendingPathComponent(".pairing-helper-new")
        if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
        try fm.copyItem(at: source, to: staged)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)
        guard rename(staged.path,Config.executable.path) == 0 else { throw ToolError("Unable to replace installed binary") }
    }
    let arguments = [Config.executable.path, "run"] + (diagnostic ? ["--diagnostic"] : [])
    let plist: [String:Any] = ["Label": Config.label, "ProgramArguments": arguments,
        "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 10,
        "LimitLoadToSessionType": "Aqua", "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null",
        "SoftResourceLimits": ["Core": 0]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: Config.plist, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.plist.path)
    try Config.managedCommand.install()
    try start()
    print("PairHop \(Config.version) installed.\nCommand: \(Config.commandLink.path)\nMode: \(diagnostic ? "diagnostic only (no input)" : "automatic pairing")\nGrant Accessibility to pairing-helper in System Settings if prompted, then run pairhop status.")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first ?? "help" {
    case "install": try install(diagnostic: args.contains("--diagnostic"))
    case "start": try start(); print("Started; login startup enabled.")
    case "stop": try stop(); print("Stopped; login startup disabled.")
    case "status", "diagnose":
        let pid = launchPID()
        // status must not repair listeners and conceal a trigger failure.
        // Explicit diagnose remains the active refresh/inspection command.
        if args.first == "diagnose", let pid {
            let before = (try? FileManager.default.attributesOfItem(atPath: Config.state.path)[.modificationDate]) as? Date
            kill(pid,SIGUSR1)
            // Only this user-invoked CLI waits. The daemon has no polling timer.
            for _ in 0..<40 {
                Thread.sleep(forTimeInterval: 0.05)
                let after = (try? FileManager.default.attributesOfItem(atPath: Config.state.path)[.modificationDate]) as? Date
                if after != before { break }
            }
        }
        print("launchd: \(pid.map { "running (pid \($0))" } ?? "not running")")
        if let d = try? Data(contentsOf: Config.state) { print(String(decoding:d,as:UTF8.self)) }
    case "uninstall":
        try stop()
        try Config.managedCommand.removeIfOwned()
        if FileManager.default.fileExists(atPath: Config.plist.path) { try FileManager.default.removeItem(at: Config.plist) }
        if FileManager.default.fileExists(atPath: Config.root.path) { try FileManager.default.removeItem(at: Config.root) }
        print("Removed this tool's executable, startup configuration and records.")
    case "run":
        try FileManager.default.createDirectory(at: Config.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = open(Config.root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock,LOCK_EX | LOCK_NB) == 0 else { throw ToolError("Another instance is running") }
        PairingService(automatic: !args.contains("--diagnostic")).run()
    case "version": print(Config.version)
    case "help", "--help", "-h": print("pairhop install [--diagnostic] | start | stop | status | diagnose | uninstall | version")
    default: throw ToolError("Unknown command. Run pairhop help.")
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
}
