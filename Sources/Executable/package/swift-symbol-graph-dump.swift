import Foundation
import Processes

public enum SwiftSymbolGraphAccessLevel:
    String,
    Sendable,
    Hashable
{
    case `private`
    case `fileprivate`
    case `internal`
    case `package`
    case `public`
    case `open`
}

public struct SwiftSymbolGraphDump:
    Sendable,
    Hashable
{
    public let files: [URL]

    public init(
        files: [URL]
    ) {
        self.files = files
    }
}

public enum SwiftSymbolGraphDumpError:
    Error,
    Sendable,
    LocalizedError
{
    case commandFailed(
        exitCode: Int,
        stderr: String
    )

    case noSymbolGraphsFound

    public var errorDescription: String? {
        switch self {
        case .commandFailed(
            let exitCode,
            let stderr
        ):
            if stderr.isEmpty {
                return "Swift package symbol-graph dump failed with exit code \(exitCode)."
            }

            return "Swift package symbol-graph dump failed with exit code \(exitCode): \(stderr)"

        case .noSymbolGraphsFound:
            return "Swift package symbol-graph dump completed without producing symbol graphs."
        }
    }
}

public extension Package {
    static func symbolGraphs(
        at directory: URL,
        minimumAccessLevel: SwiftSymbolGraphAccessLevel = .public
    ) async throws -> SwiftSymbolGraphDump {
        let result = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/env"
                ),
                arguments: [
                    "swift",
                    "package",
                    "dump-symbol-graph",
                    "--minimum-access-level",
                    minimumAccessLevel.rawValue,
                ],
                workingDirectory: directory,
                outputLimit: .max
            )
        )

        switch result.exit {
        case .exited(0):
            break

        case .exited(let code):
            throw SwiftSymbolGraphDumpError.commandFailed(
                exitCode: Int(
                    code
                ),
                stderr: result.stderrText
            )

        case .signaled(let signal):
            throw SwiftSymbolGraphDumpError.commandFailed(
                exitCode: Int(
                    128
                    + signal
                ),
                stderr: result.stderrText
            )
        }

        let buildDirectory = directory.appendingPathComponent(
            ".build",
            isDirectory: true
        )

        guard let enumerator = FileManager.default.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        ) else {
            throw SwiftSymbolGraphDumpError.noSymbolGraphsFound
        }

        let files = enumerator
            .compactMap {
                $0 as? URL
            }
            .filter {
                $0.lastPathComponent.hasSuffix(
                    ".symbols.json"
                )
            }
            .sorted {
                $0.path < $1.path
            }

        guard !files.isEmpty else {
            throw SwiftSymbolGraphDumpError.noSymbolGraphsFound
        }

        return .init(
            files: files
        )
    }
}
