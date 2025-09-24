import Foundation
import plate

public enum TargetsError: Error, LocalizedError, Sendable, PrettyError {
    case dumpFailed(exitCode: Int, stderr: String)
    case noExecutablesFound
    case decodeFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .dumpFailed(let code, _): return "swift package dump-package failed (exit \(code))"
        case .noExecutablesFound: return "No executable targets found"
        case .decodeFailed: return "Failed to decode dump-package JSON"
        }
    }

    public var failureReason: String? {
        switch self {
        case .dumpFailed(_, let err): return err.isEmpty ? "Unknown failure" : err
        case .noExecutablesFound: return "The package declares no executable targets."
        case .decodeFailed(let msg): return msg
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .dumpFailed:
            return "Run `swift package dump-package` manually to inspect errors."
        case .noExecutablesFound:
            return "Add an executable target or choose a different package directory."
        case .decodeFailed:
            return "Ensure your SwiftPM version matches the project and try again."
        }
    }

    public var helpAnchor: String? {
        switch self {
        case .dumpFailed: return "dump-package"
        case .noExecutablesFound: return "targets-executable"
        case .decodeFailed: return "json-structure"
        }
    }

    public func formatted() -> String {
        switch self {
        case .dumpFailed(let code, let stderr):
            return [
                "✖ dump-package failed (exit \(code))".ansi(.red, .bold),
                stderr.isEmpty ? nil : stderr.ansi(.red)
            ].compactMap { $0 }.joined(separator: "\n")
        case .noExecutablesFound:
            return "✖ No executable targets found".ansi(.red)
        case .decodeFailed(let msg):
            return "✖ JSON decode failed: \(msg)".ansi(.red)
        }
    }
}
