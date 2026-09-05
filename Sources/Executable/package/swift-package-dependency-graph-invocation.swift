import Foundation
import Processes

/// Executes SwiftPM's resolved dependency-graph query.
///
/// SwiftPM may perform dependency resolution and create/update its normal package
/// workspace state while answering this query. Higher-level consumers should
/// classify that preparation separately from purely observational projections.
enum SwiftPackageDependencyGraphInvocation {
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
                    "show-dependencies",
                    "--format",
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
            throw SwiftPackageGraphError.commandFailed(
                exitCode: Int(
                    code
                ),
                stderr: result.stderrText
            )

        case .signaled(let signal):
            throw SwiftPackageGraphError.commandFailed(
                exitCode: Int(
                    128 + signal
                ),
                stderr: result.stderrText
            )
        }
    }
}
