import Foundation

public enum ProcessEvaluatorError:
    Error,
    LocalizedError,
    Sendable
{
    case notMacAppEnvironment(
        String
    )

    case commandFailed(
        path: String,
        exitCode: Int32,
        stderr: String
    )

    public var errorDescription: String? {
        switch self {
        case .notMacAppEnvironment(
            let message
        ):
            return message

        case .commandFailed(
            let path,
            let exitCode,
            let stderr
        ):
            let detail = stderr.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !detail.isEmpty else {
                return "\(path) exited with status \(exitCode)."
            }

            return "\(path) exited with status \(exitCode): \(detail)"
        }
    }
}
