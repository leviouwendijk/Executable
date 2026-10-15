import Foundation
import Interfaces
import Processes
import Terminal

public enum Resolve {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: Data
        public let stderr: Data
    }

    @discardableResult
    public static func get(at dir: URL) async throws -> Result {
        try await runSwiftPackage(subcommand: "update", in: dir)
    }

    @discardableResult
    public static func resolve(at dir: URL) async throws -> Result {
        try await runSwiftPackage(subcommand: "resolve", in: dir)
    }

    @discardableResult
    private static func runSwiftPackage(subcommand: String, in dir: URL) async throws -> Result {
        // light paint, consistent with Build
        let colorables: [ColorableString] = [
            .init(selection: ["warning", "Warning"], colors: [.yellow]),
            .init(selection: ["error", "Error", "failed", "Failed"], colors: [.red, .bold]),

            .init(selection: ["updating", "Updating"], colors: [.dim]),

            .init(selection: ["resolving"], colors: [.bold]),

            .init(
                selection: [
                    "Everything is already up-to-date",
                    "Everything up-to-date",
                    "Already up-to-date"],
                colors: [.italic]
            ),

            .init(
                selection: [
                    "Working copy of",
                    "resolved at",
                    "master",
                    "main",
                    "release"
                ],
                colors: [.bold]
            ),

            .init(selection: ["https://github.com/", ".git"], colors: [.cyan]),

            // Commit-ish / short hashes parentheses & durations
            .init(selection: ["(", "s)", ")"],
                  colors: [.dim]),
            .init(selection: [" (", ")", "s)"],
                  colors: [.dim]),
        ]

        let painter: @Sendable (String) -> String = { $0.paint(colorables) }
        let streamer = LineStreamer(handle: .standardOutput, colorize: true, paint: painter)

        let processResult = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/env"
                ),
                arguments: [
                    "swift",
                    "package",
                    subcommand,
                ],
                workingDirectory: dir,
                environment: .inheritedUpdating(
                    [
                        "NSUnbufferedIO": "YES",
                    ]
                ),
                io: .pseudoTerminal,
                outputLimit: .max
            ),
            onStdout: { chunk in
                await streamer.ingest(
                    chunk
                )
            }
        )

        await streamer.flush()

        let code: Int32

        switch processResult.exit {
        case .exited(let value):
            code = value

        case .signaled(let signal):
            code =
                128
                + signal
        }

        if code != 0 {
            throw BuildError.invocationFailed(
                message: processResult.stdoutText
            )
        }

        return .init(
            exitCode: code,
            stdout: processResult.stdout,
            stderr: Data()
        )
    }
}
