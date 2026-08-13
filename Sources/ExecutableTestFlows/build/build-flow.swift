import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var buildFlow: TestFlow {
        TestFlow(
            "build",
            tags: [
                "swiftpm",
                "build",
                "pty",
                "regression",
            ]
        ) {
            Step("build fixture through PTY path") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let result = try await Build.build(
                    at: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    )
                )

                try Expect.equal(
                    result.exitCode,
                    Int32(0),
                    "debug build exits zero"
                )

                try Expect.equal(
                    result.stderr,
                    Data(),
                    "PTY-backed build keeps stderr empty"
                )

                try Expect.equal(
                    result.buildDirComponent,
                    "debug",
                    "build result retains debug directory component"
                )

                let isDebug: Bool

                switch result.mode {
                case .debug:
                    isDebug = true

                case .release:
                    isDebug = false
                }

                try Expect.true(
                    isDebug,
                    "build result retains debug mode"
                )

                let binary = fixture.root
                    .appendingPathComponent(
                        ".build/debug/FixtureCLI"
                    )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: binary.path
                    ),
                    "build produces FixtureCLI binary"
                )
            }

            Step("build failure preserves merged PTY diagnostics") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                try fixture.breakCLICompilation()

                var observedFailure = false
                var observedExitCode = 0
                var observedStdout = ""
                var observedStderr = ""

                do {
                    _ = try await Build.build(
                        at: fixture.root,
                        config: .init(
                            mode: .debug,
                            updateBuiltOnSuccess: false
                        )
                    )
                } catch BuildError.swiftFailed(
                    let exitCode,
                    let stdout,
                    let stderr
                ) {
                    observedFailure = true
                    observedExitCode = exitCode
                    observedStdout = stdout
                    observedStderr = stderr
                }

                try Expect.true(
                    observedFailure,
                    "invalid Swift source surfaces BuildError.swiftFailed"
                )

                try Expect.true(
                    observedExitCode != 0,
                    "failed build preserves nonzero exit code"
                )

                try Expect.true(
                    observedStdout.lowercased().contains(
                        "error"
                    ),
                    "PTY transcript retains compiler diagnostics"
                )

                try Expect.equal(
                    observedStderr,
                    "",
                    "PTY build failure keeps dedicated stderr empty"
                )
            }

            Step("clean removes built fixture products") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                _ = try await Build.build(
                    at: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    )
                )

                let binary = fixture.root
                    .appendingPathComponent(
                        ".build/debug/FixtureCLI"
                    )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: binary.path
                    ),
                    "fixture binary exists before clean"
                )

                try await Build.clean(
                    at: fixture.root
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: binary.path
                    ),
                    "swift package clean removes built binary"
                )
            }
        }
    }
}
