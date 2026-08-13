import Foundation
import Processes

enum SwiftPackageDumpInvocation {
    static func data(
        in packageDirectory: URL
    ) async throws -> Data {
        let result = try await ProcessRunner().run(
            .init(
                executable: .path(
                    "/usr/bin/env"
                ),
                arguments: [
                    "swift",
                    "package",
                    "dump-package",
                ],
                workingDirectory: packageDirectory,
                outputLimit: .max
            )
        )

        switch result.exit {
        case .exited(0):
            return result.stdout

        case .exited(let code):
            throw TargetsError.dumpFailed(
                exitCode: Int(
                    code
                ),
                stderr: result.stderrText
            )

        case .signaled(let signal):
            throw TargetsError.dumpFailed(
                exitCode: Int(
                    128
                    + signal
                ),
                stderr: result.stderrText
            )
        }
    }
}
