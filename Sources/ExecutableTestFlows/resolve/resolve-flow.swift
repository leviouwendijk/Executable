import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var resolveFlow: TestFlow {
        TestFlow(
            "resolve",
            tags: [
                "swiftpm",
                "resolve",
                "pty",
                "regression",
            ]
        ) {
            Step("resolve dependency-free package") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let result = try await Resolve.resolve(
                    at: fixture.root
                )

                try Expect.equal(
                    result.exitCode,
                    Int32(0),
                    "swift package resolve exits zero"
                )

                try Expect.equal(
                    result.stderr,
                    Data(),
                    "PTY-backed resolve keeps stderr empty"
                )
            }

            Step("update dependency-free package") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let result = try await Resolve.get(
                    at: fixture.root
                )

                try Expect.equal(
                    result.exitCode,
                    Int32(0),
                    "swift package update exits zero"
                )

                try Expect.equal(
                    result.stderr,
                    Data(),
                    "PTY-backed update keeps stderr empty"
                )
            }
        }
    }
}
