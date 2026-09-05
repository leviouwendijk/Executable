import Foundation
import Processes

/// Executes SwiftPM's resolved root-package description query.
///
/// This is used for facts SwiftPM computes from the manifest and filesystem,
/// including exact target source membership. It is intentionally separate from
/// `dump-package`, which represents manifest declaration semantics.
enum SwiftPackageDescriptionInvocation {
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
                    "describe",
                    "--type",
                    "json",
                ],
                workingDirectory:
                    packageDirectory,
                outputLimit: .max
            )
        )

        switch result.exit {
        case .exited(0):
            return result.stdout

        case .exited(let code):
            throw SwiftPackageSourceInventoryError.commandFailed(
                exitCode: Int(
                    code
                ),
                stderr: result.stderrText
            )

        case .signaled(let signal):
            throw SwiftPackageSourceInventoryError.commandFailed(
                exitCode: Int(
                    128
                    + signal
                ),
                stderr: result.stderrText
            )
        }
    }
}
