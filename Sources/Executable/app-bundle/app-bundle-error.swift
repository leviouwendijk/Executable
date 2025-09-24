import Foundation
import plate

public enum AppBundleError: Error, LocalizedError, Sendable, PrettyError {
    case binaryNotFound(URL)
    case infoPlistNotFound(search: [URL])
    case symlinkFailed(dest: URL, to: URL, underlying: String)
    case writeFailed(URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let u):
            return "Binary not found at \(u.path)"
        case .infoPlistNotFound:
            return "Info.plist not found"
        case .symlinkFailed(let dest, _, _):
            return "Failed to create symlink at \(dest.path)"
        case .writeFailed(let url, _):
            return "Failed to write file \(url.lastPathComponent)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .binaryNotFound:
            return "The expected executable was not produced in the build directory."
        case .infoPlistNotFound(let search):
            let paths = search.map { $0.path }.joined(separator: ", ")
            return "Searched: \(paths)"
        case .symlinkFailed(_, _, let why),
             .writeFailed(_, let why):
            return why
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .binaryNotFound:
            return "Build the target first (`swift build -c release`) or pass the correct target/binary name."
        case .infoPlistNotFound:
            return "Provide a project Info.plist or use the default generator strategy."
        case .symlinkFailed:
            return "Ensure destination is writable and not an existing regular file; delete and retry."
        case .writeFailed:
            return "Check permissions and free disk space."
        }
    }

    public var helpAnchor: String? {
        switch self {
        case .binaryNotFound: return "appbundle-binary"
        case .infoPlistNotFound: return "appbundle-infoplist"
        case .symlinkFailed: return "appbundle-symlink"
        case .writeFailed: return "appbundle-write"
        }
    }

    public func formatted() -> String {
        switch self {
        case .binaryNotFound(let u):
            return "✖ Missing binary: \(u.path)".ansi(.red)
        case .infoPlistNotFound(let search):
            return "✖ Info.plist not found. Searched:\n" + search.map { "  • \($0.path)" }.joined(separator: "\n").ansi(.red)
        case .symlinkFailed(let dest, let to, let why):
            return """
            ✖ Symlink failed
              dest: \(dest.path)
              to:   \(to.path)
              why:  \(why)
            """.ansi(.red)
        case .writeFailed(let url, let why):
            return "✖ Write failed at \(url.path): \(why)".ansi(.red)
        }
    }
}
