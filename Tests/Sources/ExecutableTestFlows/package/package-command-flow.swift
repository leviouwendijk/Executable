import Arguments
import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var packageCommandFlow: TestFlow {
        TestFlow(
            "package-command",
            tags: [
                "swiftpm",
                "arguments",
                "package",
                "pack",
            ]
        ) {
            Step("sbm root defaults to native build command") {
                let invocation = try Arguments.parse(
                    [],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    invocation.commandPath.map(\.rawValue),
                    [
                        "sbm",
                        "build",
                    ],
                    "sbm root resolves to native build default child"
                )
            }

            Step("pack defaults to get") {
                let invocation = try Arguments.parse(
                    [
                        "pack",
                    ],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    invocation.commandPath.map(\.rawValue),
                    [
                        "sbm",
                        "pack",
                        "get",
                    ],
                    "pack resolves to get default child"
                )
            }

            Step("package update and resolve use canonical Executable API") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let update = try await Package.update(
                    at: fixture.root
                )

                try Expect.equal(
                    update.exitCode,
                    Int32(0),
                    "Package.update exits zero"
                )

                let resolve = try await Package.resolve(
                    at: fixture.root
                )

                try Expect.equal(
                    resolve.exitCode,
                    Int32(0),
                    "Package.resolve exits zero"
                )
            }

            Step("pack get build uses project-default typed build workflow") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let buildObject = fixture.root.appendingPathComponent(
                    "build-object.pkl"
                )

                try """
                uuid = "00000000-0000-0000-0000-000000000002"
                name = "ExecutableFixture"
                types {
                    "binary"
                }
                versions {
                    release {
                        major = 1
                        minor = 0
                        patch = 0
                    }
                }
                compile {
                    use = true
                    arguments { "--debug" "--local" "--products" "fixture-cli" }
                }
                details = ""
                author = ""
                update = ""
                """.write(
                    to: buildObject,
                    atomically: true,
                    encoding: .utf8
                )

                let exitCode = await SwiftBuildManagerCommand.run(
                    arguments: [
                        "pack",
                        "get",
                        "--dir",
                        fixture.root.path,
                        "--build",
                    ]
                )

                try Expect.equal(
                    exitCode,
                    Int32(0),
                    "pack get --build exits zero"
                )

                let binary = fixture.root.appendingPathComponent(
                    ".build/debug/fixture-cli"
                )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: binary.path
                    ),
                    "pack build leaves local build artifact when project defaults request --local"
                )
            }
        }
    }
}
