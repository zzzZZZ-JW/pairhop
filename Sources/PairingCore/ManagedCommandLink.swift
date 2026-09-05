import Foundation

/// Ownership applies to this exact link destination, including dangling links.
public struct ManagedCommandLink {
    public let url: URL
    public let target: URL

    public init(url: URL, target: URL) { self.url = url; self.target = target }

    public var isOwned: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == target.path
    }

    public func validate() throws {
        if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil && !isOwned {
            throw Conflict(path: url.path)
        }
    }

    public func install() throws {
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !isOwned { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target) }
    }

    public func removeIfOwned() throws {
        if isOwned { try FileManager.default.removeItem(at: url) }
    }

    private struct Conflict: Error, CustomStringConvertible {
        let path: String
        var description: String { "\(path) already exists and does not belong to PairHop. Move it before installing." }
    }
}
