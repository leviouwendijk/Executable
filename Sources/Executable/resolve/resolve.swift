import Foundation
import Interfaces
import plate

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

        var childEnv = ProcessInfo.processInfo.environment
        childEnv["NSUnbufferedIO"] = "YES"

        let res = try runPTY(
            "/usr/bin/env",
            ["swift", "package", subcommand],
            env: childEnv,
            cwd: dir,
            onChunk: { chunk in
                Task.detached { await streamer.ingest(chunk) }
            }
        )

        await streamer.flush()

        if res.exitCode != 0 {
            // surface whatever we captured (PTY merges streams)
            let out = String(data: res.stdout, encoding: .utf8) ?? ""
            throw BuildError.invocationFailed(message: out) // reuse existing pretty error
        }
        return .init(exitCode: res.exitCode, stdout: res.stdout, stderr: Data())
    }
}
