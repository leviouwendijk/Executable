// runSwift alternative implementations

// public extension Build {
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

// }
