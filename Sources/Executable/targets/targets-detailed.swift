import Foundation
import Interfaces

public enum ExecutableRole: String, Sendable { case cli, app, other }

public struct ExecutableTarget: Sendable {
    public let name: String
    public let path: String?
    public let role: ExecutableRole
}

public enum TargetsDetailed {
    public static func list(in packageDir: URL) async throws -> [ExecutableTarget] {
        let data = try await dumpPackageData(in: packageDir)
        let blob = SwiftPackageDumpBlob(raw: data)
        let reader = try SwiftPackageDumpReader(blob: blob)

        let rawTargets = reader.allTargets()
        let execs = rawTargets.compactMap { dict -> ExecutableTarget? in
            guard (try? dict["type"]?.stringValue) == "executable",
                  let name = try? dict["name"]?.stringValue else { return nil }
            let path = try? dict["path"]?.stringValue
            return .init(name: name, path: path, role: guessRole(name: name, path: path))
        }

        if execs.isEmpty { throw TargetsError.noExecutablesFound }
        return execs
    }

    private static func dumpPackageData(in packageDir: URL) async throws -> Data {
        var opt = Shell.Options(); opt.cwd = packageDir
        let r = try await Shell(.zsh).run("/usr/bin/env", ["swift","package","dump-package"], options: opt)
        if let code = r.exitCode, code != 0 {
            throw TargetsError.dumpFailed(exitCode: Int(code), stderr: r.stderrText())
        }
        return r.stdout
    }

    private static func guessRole(name: String, path: String?) -> ExecutableRole {
        let s = (name + " " + (path ?? "")).lowercased()
        if s.contains("cli") || s.contains("tool") || s.contains("cmd") { return .cli }
        if s.contains("app") || s.contains("application") { return .app }
        return .other
    }
}
