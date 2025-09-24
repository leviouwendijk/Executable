import Foundation
import plate

public enum DeployError: Error, LocalizedError, Sendable, PrettyError {
    case sourceMissing(URL)
    case createDirectoryFailed(URL, underlying: String)
    case replaceFailed(src: URL, dst: URL, underlying: String)
    case metadataWriteFailed(URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let u): return "Source binary not found at \(u.path)"
        case .createDirectoryFailed(let u, _): return "Failed to create directory \(u.path)"
        case .replaceFailed(_, let dst, _): return "Failed to place binary at \(dst.path)"
        case .metadataWriteFailed(let u, _): return "Failed to write metadata at \(u.path)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .sourceMissing:
            return "Build did not produce the expected executable."
        case .createDirectoryFailed(_, let underlying),
             .replaceFailed(_, _, let underlying),
             .metadataWriteFailed(_, let underlying):
            return underlying
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .sourceMissing:
            return "Ensure the target was built for the selected configuration and name matches the executable."
        case .createDirectoryFailed:
            return "Check permissions and that the destination path is writable."
        case .replaceFailed:
            return "Verify the destination is not locked and that you have write permissions."
        case .metadataWriteFailed:
            return "Check disk space and permissions; you may delete stale .metadata and retry."
        }
    }

    public var helpAnchor: String? {
        switch self {
        case .sourceMissing: return "deploy-source"
        case .createDirectoryFailed: return "deploy-destination"
        case .replaceFailed: return "deploy-replace"
        case .metadataWriteFailed: return "deploy-metadata"
        }
    }

    public func formatted() -> String {
        switch self {
        case .sourceMissing(let u):
            return "✖ Missing source binary: \(u.path)".ansi(.red)
        case .createDirectoryFailed(let u, let why):
            return "✖ Could not create \(u.path): \(why)".ansi(.red)
        case .replaceFailed(let src, let dst, let why):
            return """
            ✖ Deploy failed
              src: \(src.path)
              dst: \(dst.path)
              why: \(why)
            """.ansi(.red)
        case .metadataWriteFailed(let u, let why):
            return "⚠︎ Metadata write failed at \(u.path): \(why)".ansi(.yellow)
        }
    }
}
