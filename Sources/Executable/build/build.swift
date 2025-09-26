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
    public static func build(at dir: URL, config: Config) async throws -> BuildResult {
        let result = try await runSwift(command: config.buildArgs, in: dir)

        if config.updateBuiltOnSuccess {
            do {
                try updateBuiltVersionSnapshot(at: dir)
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

    // USE LINESTREAMER

    // @discardableResult
    // private static func runSwift(command: [String], in dir: URL) async throws -> BuildResult {
    //     var opt = Shell.Options()
    //     opt.cwd = dir

    //     // mirror sbm’s streamed output with light paint
    //     let colorables: [ColorableString] = [
    //         .init(selection: ["production", "debugging"], colors: [.bold]),
    //         .init(selection: ["error"], colors: [.red]),
    //         .init(selection: ["warning"], colors: [.yellow]),
    //         .init(selection: ["Build complete!"], colors: [.green])
    //     ]

    //     // NEW: USING LINESTREAMER INVOCATION
    //     let painter: @Sendable (String) -> String = { $0.paint(colorables) }

    //     let outStreamer = LineStreamer(handle: .standardOutput, colorize: true, paint: painter)
    //     let errStreamer = LineStreamer(handle: .standardError,  colorize: true, paint: painter)

    //     opt.teeToStdout = false
    //     opt.teeToStderr = false

    //     opt.onStdoutChunk = { chunk in
    //         debugDumpChunk(label: "STDOUT", chunk: chunk)
    //         Task.detached(priority: .userInitiated) { await outStreamer.ingest(chunk) }
    //     }
    //     opt.onStderrChunk = { chunk in
    //         debugDumpChunk(label: "STDERR", chunk: chunk)
    //         Task.detached(priority: .userInitiated) { await errStreamer.ingest(chunk) }
    //     }

    //     let res = try await Shell(.zsh).run(
    //         "/usr/bin/env",
    //         ["swift"] + command,
    //         options: opt
    //     )

    //     await outStreamer.flush()
    //     await errStreamer.flush()

    //     let code = res.exitCode ?? 0
    //     if code != 0 {
    //         let out = String(data: res.stdout, encoding: .utf8) ?? ""
    //         let err = res.stderrText()
    //         throw BuildError.swiftFailed(exitCode: Int(code), stdout: out, stderr: err)
    //     }

    //     let mode: Config.Mode = command.contains { $0.lowercased() == "debug" } ? .debug : .release

    //     return BuildResult(
    //         exitCode: Int32(code),
    //         stdout: res.stdout,
    //         stderr: res.stderr,
    //         mode: mode,
    //         buildDirComponent: (mode == .debug ? "debug" : "release")
    //     )
    //     // END OF NEW LINESTREAMER INVOCATION
    // }

    // // COLORING, BUT NO STREAM
    // @discardableResult
    // private static func runSwift(command: [String], in dir: URL) async throws -> BuildResult {
    //     var opt = Shell.Options()
    //     opt.cwd = dir

    //     // mirror sbm’s streamed output with light paint
    //     let colorables: [ColorableString] = [
    //         .init(selection: ["production", "debugging"], colors: [.bold]),
    //         .init(selection: ["error"], colors: [.red]),
    //         .init(selection: ["warning"], colors: [.yellow]),
    //         .init(selection: ["Build complete!"], colors: [.green])
    //     ]

    //     // PREVIOUS: STILL PAINT, BUT NO CHUNK STREAMING
    //     opt.teeToStdout = false
    //     opt.teeToStderr = false
    //     opt.onStdoutChunk = { chunk in
    //         if let t = String(data: chunk, encoding: .utf8) { print(t.paint(colorables), terminator: "") }
    //         else { FileHandle.standardOutput.write(chunk) }
    //     }
    //     opt.onStderrChunk = { chunk in
    //         if let t = String(data: chunk, encoding: .utf8) { fputs(t.paint(colorables), stderr) }
    //         else { FileHandle.standardError.write(chunk) }
    //     }

    //     do {
    //         let res = try await Shell(.zsh).run("/usr/bin/env", ["swift"] + command, options: opt)
    //         let code = res.exitCode ?? 0
    //         if code != 0 {
    //             let out = String(data: res.stdout, encoding: .utf8) ?? ""
    //             let err = res.stderrText()
    //             throw BuildError.swiftFailed(exitCode: Int(code), stdout: out, stderr: err)
    //         }

    //         // best-effort guess for mode from args
    //         let mode: Config.Mode = command.contains(where: { $0.lowercased() == "debug" }) ? .debug : .release
    //         return BuildResult(
    //             exitCode: Int32(code),
    //             stdout: res.stdout,
    //             stderr: res.stderr,
    //             mode: mode,
    //             buildDirComponent: (mode == .debug ? "debug" : "release")
    //         )
    //     } catch {
    //         // keep parity with sbm’s stderr surfacing
    //         fputs("\(error)\n", stderr)
    //         throw error
    //     }
    // }

    // @discardableResult
    // private static func runSwift(command: [String], in dir: URL) async throws -> BuildResult {
    //     var opt = Shell.Options()
    //     opt.cwd = dir

    //     // mirror sbm’s streamed output with light paint
    //     let colorables: [ColorableString] = [
    //         .init(selection: ["production", "debugging"], colors: [.bold]),
    //         .init(selection: ["error"], colors: [.red]),
    //         .init(selection: ["warning"], colors: [.yellow]),
    //         .init(selection: ["Build complete!"], colors: [.green])
    //     ]

    //     let painter: @Sendable (String) -> String = { $0.paint(colorables) }

    //     let outStreamer = LineStreamer(handle: .standardOutput, colorize: true, paint: painter)
    //     let errStreamer = LineStreamer(handle: .standardError,  colorize: true, paint: painter)

    //     opt.teeToStdout = true
    //     opt.teeToStderr = true

    //     opt.onStdoutChunk = nil
    //     opt.onStderrChunk = nil

    //     let res = try await Shell(.zsh).run(
    //         "/usr/bin/env",
    //         ["swift"] + command,
    //         options: opt
    //     )

    //     await outStreamer.flush()
    //     await errStreamer.flush()

    //     let code = res.exitCode ?? 0
    //     if code != 0 {
    //         let out = String(data: res.stdout, encoding: .utf8) ?? ""
    //         let err = res.stderrText()
    //         throw BuildError.swiftFailed(exitCode: Int(code), stdout: out, stderr: err)
    //     }

    //     let mode: Config.Mode = command.contains { $0.lowercased() == "debug" } ? .debug : .release

    //     return BuildResult(
    //         exitCode: Int32(code),
    //         stdout: res.stdout,
    //         stderr: res.stderr,
    //         mode: mode,
    //         buildDirComponent: (mode == .debug ? "debug" : "release")
    //     )
    // }

    private static func updateBuiltVersionSnapshot(at dir: URL) throws {
        let url = try BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: dir, maxDepth: 6, buildFile: "build-object.pkl"
        )
        let cfg = try BuildObjectConfiguration(from: url)

        if cfg.versions.built == cfg.versions.repository { return }
        
        let newly_updated_built = cfg.versions.repository

        // write updated config with built := repository
        let updated = BuildObjectConfiguration(
            uuid: cfg.uuid,
            name: cfg.name,
            types: cfg.types,
            versions: .init(
                built: newly_updated_built,
                repository: cfg.versions.repository
            ),
            compile: cfg.compile,
            details: cfg.details,
            author: cfg.author,
            update: cfg.update
        )
        try updated.write(to: url)

        let v = cfg.versions.repository
        print("Updated built version → \(v.major).\(v.minor).\(v.patch)")
    }
}

@inline(__always)
private func nowMillis() -> UInt64 {
    let t = DispatchTime.now().uptimeNanoseconds
    return t / 1_000_000
}

private func countCRLF(in data: Data) -> (cr: Int, lf: Int) {
    var cr = 0, lf = 0
    for b in data { if b == 0x0D { cr += 1 } else if b == 0x0A { lf += 1 } }
    return (cr, lf)
}

private func escapedPreview(_ data: Data, limit: Int = 120) -> String {
    var s = ""
    var shown = 0
    for b in data {
        if shown >= limit { s += "…"; break }
        switch b {
        case 0x20...0x7E:
            s.append(Character(UnicodeScalar(b)))
        case 0x0A: s += "\\n"
        case 0x0D: s += "\\r"
        case 0x09: s += "\\t"
        case 0x1B: s += "\\e"   // ESC
        default:
            s += String(format: "\\x%02X", b)
        }
        shown += 1
    }
    return s
}

private func debugDumpChunk(label: String, chunk: Data) {
    let (cr, lf) = countCRLF(in: chunk)
    let ts = nowMillis()
    let meta = "[\(ts)] \(label) chunk \(chunk.count)B cr:\(cr) lf:\(lf)"
    let prev = escapedPreview(chunk)
    FileHandle.standardError.write(Data(("\(meta) | \(prev)\n").utf8))
}
