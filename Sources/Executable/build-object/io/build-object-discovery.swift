import Foundation
import Path

/// Domain-specific filename lookup; the ancestor algorithm is supplied by Path/IO.
public enum BuildObjectDiscovery {
    public static func nearest(
        named filename: String,
        from startURL: URL = Bundle.main.bundleURL,
        maxDepth: Int = 5
    ) throws -> URL {
        // Original traversal tested at most maxDepth directories, including the start.
        guard maxDepth > 0 else {
            throw BuildObjectDiscoveryError.notFound(filename: filename, maxDepth: maxDepth, startURL: startURL)
        }
        guard let ancestor = PathAncestorSearch.nearestAncestorContainingAny(
            [filename],
            startingAt: startURL,
            treatingStartAsDirectory: true,
            includingStart: true,
            maxDepth: maxDepth - 1
        ) else {
            throw BuildObjectDiscoveryError.notFound(filename: filename, maxDepth: maxDepth, startURL: startURL)
        }
        return ancestor.appendingPathComponent(filename)
    }
}

public enum BuildObjectDiscoveryError: Error, LocalizedError, Sendable {
    case notFound(filename: String, maxDepth: Int, startURL: URL)

    public var errorDescription: String? {
        switch self {
        case .notFound(let filename, let maxDepth, let startURL):
            return "Could not find '\(filename)' within \(maxDepth) levels starting at \(startURL.path)"
        }
    }
}

/// Source-compatible wrapper only; no second hand-written ancestor search.
@available(*, deprecated, message: "Use Executable.BuildObjectDiscovery.nearest(named:from:maxDepth:)")
public func traversingSearch(
    from startURL: URL = Bundle.main.bundleURL,
    maxDepth: Int = 5,
    searching targetFile: String
) throws -> URL {
    try BuildObjectDiscovery.nearest(named: targetFile, from: startURL, maxDepth: maxDepth)
}
