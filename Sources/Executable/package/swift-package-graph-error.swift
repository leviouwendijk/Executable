import Foundation

public enum SwiftPackageGraphError:
    Error,
    Sendable,
    LocalizedError
{
    case commandFailed(
        exitCode: Int,
        stderr: String
    )

    case decodeFailed(
        message: String
    )

    public var errorDescription: String? {
        switch self {
        case .commandFailed(
            let exitCode,
            _
        ):
            return "swift package show-dependencies failed (exit \(exitCode))"

        case .decodeFailed:
            return "Failed to decode SwiftPM dependency graph JSON"
        }
    }

    public var failureReason: String? {
        switch self {
        case .commandFailed(
            _,
            let stderr
        ):
            return stderr.isEmpty
                ? "SwiftPM did not provide an error message."
                : stderr

        case .decodeFailed(
            let message
        ):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .commandFailed:
            return "Run `swift package show-dependencies --format json` in the package root and inspect SwiftPM diagnostics."

        case .decodeFailed:
            return "Confirm the active SwiftPM toolchain's show-dependencies JSON schema and retry."
        }
    }
}
