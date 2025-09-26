import Foundation
import plate
import Interfaces

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
                fputs("note: failed to update built version snapshot: \(error)\n", stderr)
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

    // USE PTY
    @discardableResult
    private static func runSwift(command: [String], in dir: URL) async throws -> BuildResult {
        // mirror sbm’s streamed output with light paint
        let colorables: [ColorableString] = [
            .init(selection: ["production", "debugging"], colors: [.bold]),
            .init(selection: ["error"], colors: [.red]),
            .init(selection: ["warning"], colors: [.yellow]),
            .init(selection: ["Build complete!"], colors: [.green])
        ]
        let painter: @Sendable (String) -> String = { $0.paint(colorables) }

        let outStreamer = LineStreamer(handle: .standardOutput, colorize: true, paint: painter)

        var childEnv = ProcessInfo.processInfo.environment
        childEnv["NSUnbufferedIO"] = "YES"

        let resPTY = try runPTY(
            "/usr/bin/env",
            ["swift"] + command,
            env: childEnv,
            cwd: dir,
            onChunk: { chunk in
                // debugDumpChunk(label: "PTY", chunk: chunk)
                Task.detached(priority: .userInitiated) { await outStreamer.ingest(chunk) }
            }
        )

        await outStreamer.flush()

        let code = resPTY.exitCode
        if code != 0 {
            let out = String(data: resPTY.stdout, encoding: .utf8) ?? ""
            throw BuildError.swiftFailed(exitCode: Int(code), stdout: out, stderr: "")
        }

        let mode: Config.Mode = command.contains { $0.lowercased() == "debug" } ? .debug : .release
        return BuildResult(
            exitCode: code,
            stdout: resPTY.stdout,
            stderr: Data(),
            mode: mode,
            buildDirComponent: (mode == .debug ? "debug" : "release")
        )
    }

    private static func updateBuiltVersionSnapshot(at dir: URL, argv: [String]? = nil) throws {
        // get build-object.pkl
        let obj_url = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: dir, maxDepth: 6, buildFile: "build-object.pkl"
        )
        let obj_cfg = try BuildObjectConfiguration(from: obj_url)

        // get compiled.pkl
        let compl_url = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: dir, maxDepth: 6, buildFile: "compiled.pkl"
        )
        let compl_cfg = try CompiledLocalBuildObject(from: compl_url)

        let compiled = compl_cfg.version
        let release = obj_cfg.versions.release

        if compiled == release { return }
        
        // // write updated config with built := repository
        // let updated = BuildObjectConfiguration(
        //     uuid: cfg.uuid,
        //     name: cfg.name,
        //     types: cfg.types,
        //     versions: .init(
        //         built: newly_updated_built,
        //         repository: cfg.versions.repository
        //     ),
        //     compile: cfg.compile,
        //     details: cfg.details,
        //     author: cfg.author,
        //     update: cfg.update
        // )
        // try updated.write(to: url)

        let updated = CompiledLocalBuildObject(
            version: release,
            arguments: argv ?? []
        )
        try updated.write(to: compl_url)

        print("Updated built version → \(release.major).\(release.minor).\(release.patch)")
    }
}
