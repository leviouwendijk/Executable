import Foundation
import Interfaces

/// Build-object-aware remote operations live downstream of generic Git/HTTP transport.
/// These extend the existing GitRepo namespace without introducing Interfaces -> Executable.
public extension GitRepo {
    static func fetchRemoteBuildObject(
        _ directoryURL: URL,
        filename: String = "build-object.pkl",
        ref: String? = nil
    ) async throws -> BuildObjectConfiguration {
        let source = try await fetchRemoteFile(directoryURL, path: filename, ref: ref)
        return try BuildObjectConfiguration.parseCompatible(source)
    }

    static func fetchBuildObject(
        fromUpdateURL urlString: String
    ) async throws -> BuildObjectConfiguration {
        let source = try await fetchText(fromUpdateURL: urlString)
        return try BuildObjectConfiguration.parseCompatible(source)
    }
}

public extension BuildObjectConfiguration {
    /// Preserve the historical modern-first, then legacy-modernization behavior.
    /// Parsing is independent on each attempt; no mutable PklParser cursor or reset is needed.
    static func parseCompatible(_ source: String) throws -> Self {
        if let modern = try? Self.parse(source) {
            return modern
        }
        return try LegacyObject.parse(source).modernize()
    }
}
