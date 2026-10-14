import Foundation
import Path

/// Domain-specific filename lookup; the ancestor algorithm is supplied by Path/IO.
public enum BuildObjectDiscovery {
    /// Resolve a file only in the designated project directory, never an ancestor.
    /// PathAncestorSearch delegates existence checks to IO.FileSystem.
    public static func local(named filename: String, in project: URL) throws -> URL? {
        let root = project.standardizedFileURL
        guard let containing = PathAncestorSearch.nearestAncestorContainingAny(
            [filename],
            startingAt: root,
            treatingStartAsDirectory: true,
            includingStart: true,
            maxDepth: 0
        ) else {
            return nil
        }
        let file = containing.appendingPathComponent(filename).standardizedFileURL
        try requireOwned(file, by: root)
        return file
    }

    public static func requireLocal(named filename: String, in project: URL) throws -> URL {
        if let file = try local(named: filename, in: project) { return file }
        throw BuildObjectDiscoveryError.notFound(filename: filename, maxDepth: 1, startURL: project)
    }

    /// Reject a symlinked configuration, compiled file or gitignore that would escape the root.
    /// This also works before the destination file exists.
    public static func requireOwned(_ file: URL, by project: URL) throws {
        let root = project.resolvingSymlinksInPath().standardizedFileURL
        let parent = file.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent()
        guard parent == root else {
            throw BuildObjectDiscoveryError.outsideProject(file: file, project: project)
        }
    }

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
    case outsideProject(file: URL, project: URL)
    case ancestorNotApproved(URL)
    case ancestorConfirmationDeclined(URL)
    case inheritanceOptionsConflict
    case configurationOverridesProject(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let filename, let maxDepth, let startURL):
            return "Could not find '\(filename)' within \(maxDepth) levels starting at \(startURL.path)"
        case .outsideProject(let file, let project):
            return "Refusing path outside project \(project.path): \(file.path)"
        case .ancestorNotApproved(let file):
            return "Ancestor build-object configuration not explicitly approved: \(file.path)"
        case .ancestorConfirmationDeclined(let file):
            return "Ancestor configuration was not confirmed: \(file.path)"
        case .inheritanceOptionsConflict:
            return "--inherit-ancestor may only be combined with --project. Pass other build flags without inheritance."
        case .configurationOverridesProject(let value):
            return "Stored build-object.pkl compile arguments may not override the project using --project (found \(value))."
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
