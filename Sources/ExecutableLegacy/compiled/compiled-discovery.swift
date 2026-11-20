import Executable
import Foundation

public extension BuildObjectDiscovery {
    /// What the last local build of a build-object.pkl project produced.
    static let legacyCompiled = "compiled.pkl"

    static func compiledURL(for configuration: URL) -> URL {
        configuration.deletingLastPathComponent().appendingPathComponent(legacyCompiled)
    }

    static func compiled(for configuration: URL) throws -> URL? {
        try local(named: legacyCompiled, in: configuration.deletingLastPathComponent())
    }
}
