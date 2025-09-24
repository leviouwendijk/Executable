import Foundation
import plate
import Interfaces

public enum BuildLibrary {
    public struct Output: Sendable {
        public let packageName: String
        public let artifactsDir: URL        // sbm-bin/modules/<packageName>
        public let builtDir: URL            // .build/<config>
    }

    /// Build with flags for library evolution & module interface emission, then
    /// collect module artifacts into `modules/<pkg>` unless `local` is true.
    public static func buildAndExport(
        at dir: URL,
        config: Build.Config,
        local: Bool,
        modulesRoot: URL // usually ~/sbm-bin/modules
    ) async throws -> Output {
        // 1) Determine package name via dump-package (for output dir)
        let info = try await packageInfo(dir)
        let packageName = info

        // 2) Build with extra flags (matching sbm)
        let args = [
            "build", "-c", config.buildDirComponent,
            "-Xswiftc", "-enable-library-evolution",
            "-Xswiftc", "-emit-module-interface-path",
            // Emit interface into predictable path (Swift emits per-target interface files anyway;
            // we pass a writable path to satisfy the flag; actual files are under .build/<cfg>/...)
            "-Xswiftc", ".build/\(config.buildDirComponent)/Modules/\(packageName).swiftinterface",
            "-Xswiftc", "-emit-library",
            "-Xswiftc", "-emit-module"
        ]
        _ = try await runSwift(args, in: dir)

        let builtDir = dir.appendingPathComponent(".build/\(config.buildDirComponent)")

        // 3) If local, skip export
        if local {
            return .init(packageName: packageName, artifactsDir: builtDir, builtDir: builtDir)
        }

        // 4) Collect artifacts into modulesRoot/<packageName>
        let outDir = modulesRoot.appendingPathComponent(packageName, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // copy common module artifacts if present (non-fatal if some are missing)
        let suffixes = [
            ".swiftmodule", ".swiftdoc", ".swiftinterface",
            ".swiftsourceinfo", ".abi.json", ".dylib", ".a"
        ]
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: builtDir.path)) ?? []
        for item in contents {
            guard suffixes.contains(where: { item.hasSuffix($0) }) else { continue }
            let src = builtDir.appendingPathComponent(item)
            let dst = outDir.appendingPathComponent(item)
            if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
            do { try fm.copyItem(at: src, to: dst) } catch { /* ignore missing */ }
        }

        print("Library artifacts exported to \(outDir.path)".ansi(.green))
        return .init(packageName: packageName, artifactsDir: outDir, builtDir: builtDir)
    }

    private static func packageInfo(_ dir: URL) async throws -> String {
        var opt = Shell.Options(); opt.cwd = dir
        let r = try await Shell(.zsh).run("/usr/bin/env", ["swift","package","dump-package"], options: opt)
        if let code = r.exitCode, code != 0 {
            throw BuildError.invocationFailed(message: r.stderrText())
        }
        let blob = SwiftPackageDumpBlob(raw: r.stdout)
        let reader = try SwiftPackageDumpReader(blob: blob)
        let name = reader.packageName() ?? dir.lastPathComponent
        return (name)
    }

    @discardableResult
    private static func runSwift(_ command: [String], in dir: URL) async throws -> Build.BuildResult {
        try await Build.build(at: dir, config: .init(mode: (command.contains("debug") ? .debug : .release)))
    }
}
