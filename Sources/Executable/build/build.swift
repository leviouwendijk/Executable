import Foundation
import plate
import Interfaces
import Processes
import Terminal
import Indentation

public enum Build {
    public struct Config: Sendable {
        public enum Mode: Sendable { 
            case debug
            case release 
        }

        public let mode: Mode
        public let updateBuiltOnSuccess: Bool

        public init(mode: Mode, updateBuiltOnSuccess: Bool = true) {
            self.mode = mode
            self.updateBuiltOnSuccess = updateBuiltOnSuccess
        }

        public var buildArgs: [String] { mode == .debug ? ["build","-c","debug"] : ["build","-c","release"] }
        public var buildDirComponent: String { mode == .debug ? "debug" : "release" }
    }

    /// Full build with streamed output (same as `swift build -c <mode>`).
    @discardableResult
    public static func build(at dir: URL, config: Config, argv_audit: [String]? = nil) async throws -> BuildResult {
        let result = try await runSwift(command: config.buildArgs, in: dir)

        if config.updateBuiltOnSuccess {
            do {
                try updateBuiltVersionSnapshot(at: dir, argv: argv_audit)
            } catch {
                // non-fatal; surface a short diagnostic and keep going
                fputs("Note: failed to update built version snapshot:\n", stderr)
                fputs("\(error.localizedDescription.indent())\n", stderr)
            }
        }

        return result
    }

    @discardableResult
    public static func captured(
        at dir: URL,
        config: Config,
        argv_audit: [String]? = nil
    ) async throws -> BuildResult {
        let result = try await runSwift(
            command: config.buildArgs,
            in: dir,
            onOutput: nil
        )

        if config.updateBuiltOnSuccess {
            do {
                try updateBuiltVersionSnapshot(
                    at: dir,
                    argv: argv_audit
                )
            } catch {
                fputs(
                    "Note: failed to update built version snapshot:\n",
                    stderr
                )
                fputs(
                    "\(error.localizedDescription.indent())\n",
                    stderr
                )
            }
        }

        return result
    }

    /// Alias kept for clarity when a caller semantically means “build only”.
    @discardableResult
    public static func only(at dir: URL, config: Config) async throws -> BuildResult {
        try await build(at: dir, config: config)
    }

    /// `swift package clean`
    public static func clean(at dir: URL) async throws {
        _ = try await runSwift(command: ["package", "clean"], in: dir)
        print("\nClean successful!".ansi(.green))
    }

    public struct BuildResult: Sendable {
        public let exitCode: Int32
        public let stdout: Data
        public let stderr: Data
        public let mode: Config.Mode
        public let buildDirComponent: String
    }

    @discardableResult
    package static func runSwift(
        command: [String],
        in dir: URL,
        onOutput: ProcessOutputHandler? = { chunk in
            Terminal.write(
                chunk,
                to: .standardOutput
            )
        }
    ) async throws -> BuildResult {
        let processResult = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/env"
                ),
                arguments: [
                    "swift",
                ] + command,
                workingDirectory: dir,
                environment: .inheritedUpdating(
                    [
                        "NSUnbufferedIO": "YES",
                    ]
                ),
                io: .pseudoTerminal,
                outputLimit: .max
            ),
            onStdout: onOutput
        )

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
            throw BuildError.swiftFailed(
                exitCode: Int(
                    code
                ),
                stdout: processResult.stdoutText,
                stderr: ""
            )
        }

        let mode: Config.Mode = command.contains {
            $0.lowercased() == "debug"
        }
            ? .debug
            : .release

        return BuildResult(
            exitCode: code,
            stdout: processResult.stdout,
            stderr: Data(),
            mode: mode,
            buildDirComponent: mode == .debug
                ? "debug"
                : "release"
        )
    }

    // @discardableResult
    // private static func runSwift(command: [String], in dir: URL) async throws -> BuildResult {
    //     let colorables: [ColorableString] = [
    //         .init(selection: ["production", "debugging"], colors: [.bold]),
    //         .init(selection: ["error"], colors: [.red]),
    //         .init(selection: ["warning"], colors: [.yellow]),
    //         .init(selection: ["Build complete!"], colors: [.green])
    //     ]
    //     let painter: @Sendable (String) -> String = { $0.paint(colorables) }

    //     let outStreamer = LineStreamer(handle: .standardOutput, colorize: true, paint: painter)

    //     var childEnv = ProcessInfo.processInfo.environment
    //     childEnv["NSUnbufferedIO"] = "YES"

    //     let resPTY = try runPTY(
    //         "/usr/bin/env",
    //         ["swift"] + command,
    //         env: childEnv,
    //         cwd: dir,
    //         onChunk: { chunk in
    //             // debugDumpChunk(label: "PTY", chunk: chunk)
    //             Task.detached(priority: .userInitiated) { 
    //                 await outStreamer.ingest(chunk) 
    //             }
    //         }
    //     )

    //     await outStreamer.flush()

    //     let code = resPTY.exitCode
    //     if code != 0 {
    //         let out = String(data: resPTY.stdout, encoding: .utf8) ?? ""
    //         throw BuildError.swiftFailed(exitCode: Int(code), stdout: out, stderr: "")
    //     }

    //     let mode: Config.Mode = command.contains { $0.lowercased() == "debug" } ? .debug : .release
    //     return BuildResult(
    //         exitCode: code,
    //         stdout: resPTY.stdout,
    //         stderr: Data(),
    //         mode: mode,
    //         buildDirComponent: (mode == .debug ? "debug" : "release")
    //     )
    // }

    private static func updateBuiltVersionSnapshot(at dir: URL, argv: [String]? = nil) throws {
        let project = dir.standardizedFileURL
        // No local build-object means no local snapshot. Never adopt parent metadata.
        guard let objectURL = try BuildObjectDiscovery.local(
            named: "build-object.pkl", in: project
        ) else { return }
        let configuration = try BuildObjectConfiguration(from: objectURL)
        let release = configuration.versions.release
        let compiledURL = project.appendingPathComponent("compiled.pkl")
        try BuildObjectDiscovery.requireOwned(compiledURL, by: project)

        let recordedArguments = argv ?? []
        if let existing = try BuildObjectDiscovery.local(named: "compiled.pkl", in: project) {
            let compiled = try CompiledLocalBuildObject(from: existing)
            if compiled.version == release && compiled.arguments == recordedArguments {
                print("compiled version and arguments unchanged")
                print("no ".ansi(.brightBlack) + "compiled.pkl".ansi(.brightBlack, .bold) + " written".ansi(.brightBlack))
                return
            }
            print("compiled version or arguments changed")
            print("writing ".ansi(.brightBlack) + "compiled.pkl".ansi(.brightBlack, .bold) + "…".ansi(.brightBlack))
        }

        // A symlinked .gitignore could otherwise mutate a file outside the project.
        try BuildObjectDiscovery.requireOwned(project.appendingPathComponent(".gitignore"), by: project)
        let ignorable: [String] = ["compiled.pkl", "/compiled.pkl", "**/compiled.pkl"]
        do {
            let (result, context) = try GitRepo.appending(
                ignorable: ignorable, to: ".gitignore", in: project
            )
            switch result {
            case .appended:
                print("added to .gitignore: \(ignorable.joined(separator: ", "))")
                print("snippet:")
                printi(context.ansi(.brightBlack))
            case .alreadyPresent:
                break
            case .notFound:
                print(context)
            }
        } catch {
            fputs("note: could not update .gitignore: \(error)\n", stderr)
        }

        let updated = CompiledLocalBuildObject(version: release, arguments: recordedArguments)
        try updated.write(to: compiledURL)
        print("compiled version += \(release.string(prefixStyle: .none))")
    }
}
