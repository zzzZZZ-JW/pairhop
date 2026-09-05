import XCTest
@testable import PairingCore

final class ManagedCommandLinkTests: XCTestCase {
    func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testOwnedDanglingLinkCanBeReinstalledAndRemoved() throws {
        try withDirectory { directory in
            let link = ManagedCommandLink(url: directory.appendingPathComponent("bin/pairhop"), target: directory.appendingPathComponent("not-installed-yet"))
            try link.install()
            try link.install()
            XCTAssertTrue(link.isOwned)
            try link.removeIfOwned()
            XCTAssertThrowsError(try FileManager.default.destinationOfSymbolicLink(atPath: link.url.path))
        }
    }

    func testForeignFileAndDanglingLinkArePreserved() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("pairhop")
            let link = ManagedCommandLink(url: url, target: directory.appendingPathComponent("our-binary"))
            try Data("user command".utf8).write(to: url)
            XCTAssertThrowsError(try link.install())
            try link.removeIfOwned()
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "user command")
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/missing/other-command")
            XCTAssertThrowsError(try link.install())
            try link.removeIfOwned()
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: url.path), "/missing/other-command")
        }
    }
}
