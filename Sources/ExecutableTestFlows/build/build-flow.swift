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
            Step("build and clean fixture through PTY path") {
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
