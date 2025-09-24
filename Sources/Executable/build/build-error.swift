import Foundation
import plate

public enum BuildError: Error, LocalizedError, Sendable, PrettyError {
    case swiftFailed(exitCode: Int, stdout: String, stderr: String)
    case invalidWorkingDirectory(URL)
    case invocationFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case .swiftFailed(let code, _, _):
            return "Swift build failed (exit \(code))"
        case .invalidWorkingDirectory(let url):
            return "Invalid working directory: \(url.path)"
        case .invocationFailed(let msg):
            return "Failed to invoke build command: \(msg)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .swiftFailed(_, _, let stderr):
            return stderr.isEmpty ? "Unknown toolchain error" : stderr
        case .invalidWorkingDirectory:
            return "The provided directory does not exist or is not accessible."
        case .invocationFailed(let msg):
            return msg
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .swiftFailed:
            return "Run `swift build -v` manually and inspect the emitted diagnostics."
        case .invalidWorkingDirectory:
            return "Pass a readable package root directory (contains Package.swift)."
        case .invocationFailed:
            return "Verify Xcode CLTs / Swift toolchain and your PATH; try `xcode-select --install`."
        }
    }

    public var helpAnchor: String? {
        switch self {
        case .swiftFailed: return "swift-build"
        case .invalidWorkingDirectory: return "working-directory"
        case .invocationFailed: return "process-launch"
        }
    }

    public func formatted() -> String {
        switch self {
        case let .swiftFailed(code, out, err):
            return [
                "✖ ".ansi(.red, .bold) + "Swift build failed".ansi(.bold),
                "Exit code: \(code)".ansi(.brightBlack),
                err.isEmpty ? nil : "stderr:\n\(err)".ansi(.red),
                out.isEmpty ? nil : "stdout:\n\(out)".ansi(.brightBlack)
            ]
            .compactMap { $0 }.joined(separator: "\n")
        case .invalidWorkingDirectory(let url):
            return "✖ Invalid working directory: \(url.path)".ansi(.red)
        case .invocationFailed(let msg):
            return "✖ Invocation failed: \(msg)".ansi(.red)
        }
    }
}
