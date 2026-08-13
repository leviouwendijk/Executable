import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var buildLibraryFlow: TestFlow {
        TestFlow(
            "build-library",
            tags: [
                "swiftpm",
                "build-library",
                "pipes",
                "regression",
            ]
        ) {
            Step("resolve package name through dump-package") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let name = try await BuildLibrary.packageInfo(
                    fixture.root
                )

                try Expect.equal(
                    name,
                    "ExecutableFixture",
                    "package name survives dump-package decoding"
                )
            }

            Step("discover library products separately from executables") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let products = try await BuildLibrary.libraryProducts(
                    fixture.root
                )

                try Expect.equal(
                    products,
                    [
                        .init(
                            name: "FixtureCore",
                            targets: [
                                "FixtureCore",
                            ]
                        ),
                    ],
                    "only library products are selected for distribution builds"
                )
            }

            Step("preserve scoped distribution build arguments") {
                let arguments = BuildLibrary.buildArguments(
                    targetName: "FixtureCore",
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    )
                )

                try Expect.equal(
                    arguments,
                    [
                        "build",
                        "-c",
                        "debug",
                        "--target",
                        "FixtureCore",
                        "--enable-parseable-module-interfaces",
                        "-Xswiftc",
                        "-enable-library-evolution",
                    ],
                    "distribution build is scoped to the library product"
                )
            }

            Step("build library distribution artifacts end to end") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let modulesRoot = fixture.root
                    .appendingPathComponent(
                        "exported-modules",
                        isDirectory: true
                    )

                let output = try await BuildLibrary.buildAndExport(
                    at: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    ),
                    local: true,
                    modulesRoot: modulesRoot
                )

                try Expect.equal(
                    output.packageName,
                    "ExecutableFixture",
                    "BuildLibrary retains package identity"
                )

                let expectedInterface = fixture.root
                    .appendingPathComponent(
                        ".build/debug/Modules/FixtureCore.swiftinterface"
                    )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: expectedInterface.path
                    ),
                    "library target emits FixtureCore.swiftinterface"
                )

                let interface = try String(
                    contentsOf: expectedInterface,
                    encoding: .utf8
                )

                try Expect.true(
                    interface.contains(
                        "module"
                    ) || interface.contains(
                        "public"
                    ),
                    "emitted interface contains Swift interface content"
                )


                for executableName in [
                    "FixtureCLI",
                    "FixtureApp",
                    "Worker",
                ] {
                    let executable = fixture.root
                        .appendingPathComponent(
                            ".build/debug/\(executableName)"
                        )

                    try Expect.false(
                        FileManager.default.fileExists(
                            atPath: executable.path
                        ),
                        "library build does not produce \(executableName)"
                    )
                }
            }

            Step("forward arbitrary Swift arguments without reducing them to build mode") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let result = try await BuildLibrary.runSwift(
                    [
                        "--version",
                    ],
                    in: fixture.root
                )

                try Expect.equal(
                    result.exitCode,
                    Int32(0),
                    "swift --version exits zero"
                )

                let output = String(
                    decoding: result.stdout,
                    as: UTF8.self
                )

                try Expect.true(
                    output.contains(
                        "Swift version"
                    ),
                    "BuildLibrary forwards the actual Swift argument vector"
                )

                let buildDirectory = fixture.root
                    .appendingPathComponent(
                        ".build"
                    )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: buildDirectory.path
                    ),
                    "swift --version does not silently become a package build"
                )
            }
        }
    }
}
