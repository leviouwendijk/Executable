import Foundation
import Path

/// Domain-specific filename lookup; the ancestor algorithm is supplied by Path/IO.
public enum BuildObjectDiscovery {
    public static let preferredConfiguration = "build.frame"
    public static let legacyConfiguration = "build-object.pkl"

    public static func configuration(in project: URL) throws -> URL? {
        if let frame = try local(named: preferredConfiguration, in: project) { return frame }
        return try local(named: legacyConfiguration, in: project)
    }

    public static func requireConfiguration(in project: URL) throws -> URL {
        if let configuration = try configuration(in: project) { return configuration }
        throw BuildObjectDiscoveryError.notFound(
            filename: "build.frame or build-object.pkl", maxDepth: 1, startURL: project
        )
    }

    public static func nearestConfiguration(
        from startURL: URL = Bundle.main.bundleURL,
        maxDepth: Int = 5
    ) throws -> URL {
        guard maxDepth > 0,
              let ancestor = PathAncestorSearch.nearestAncestorContainingAny(
                [preferredConfiguration, legacyConfiguration],
                startingAt: startURL,
                treatingStartAsDirectory: true,
                includingStart: true,
                maxDepth: maxDepth - 1
              ) else {
            throw BuildObjectDiscoveryError.notFound(
                filename: "build.frame or build-object.pkl", maxDepth: maxDepth, startURL: startURL
            )
        }
        return try requireConfiguration(in: ancestor)
    }

    public static func compiledName(for configuration: URL) -> String {
        configuration.lastPathComponent == preferredConfiguration ? "compiled.frame" : "compiled.pkl"
    }

    public static func compiledURL(for configuration: URL) -> URL {
        configuration.deletingLastPathComponent().appendingPathComponent(compiledName(for: configuration))
    }

    public static func compiled(for configuration: URL) throws -> URL? {
        try local(named: compiledName(for: configuration), in: configuration.deletingLastPathComponent())
    }

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
