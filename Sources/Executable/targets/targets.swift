import Foundation
import Interfaces
import plate

public enum Targets {
    public static func executableNames(in packageDir: URL) async throws -> [String] {
        let data = try await dumpPackageData(in: packageDir)
        let blob = SwiftPackageDumpBlob(raw: data)
        let reader = try SwiftPackageDumpReader(blob: blob)
        let names = reader.executableTargetNames()
        if names.isEmpty {
            throw TargetsError.noExecutablesFound
        }
        return names
    }

    private static func dumpPackageData(in packageDir: URL) async throws -> Data {
        var opt = Shell.Options()
        opt.cwd = packageDir
        let r = try await Shell(.zsh).run("/usr/bin/env", ["swift","package","dump-package"], options: opt)
        if let code = r.exitCode, code != 0 {
            let e = r.stderrText()
            throw TargetsError.dumpFailed(exitCode: Int(code), stderr: e)
        }
        return r.stdout
    }
}
