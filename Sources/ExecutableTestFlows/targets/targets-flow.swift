import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var targetsFlow: TestFlow {
        TestFlow(
            "targets",
            tags: [
                "swiftpm",
                "targets",
                "regression",
            ]
        ) {
            Step("discover executable target names") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let names = try await Targets
                    .executableNames(
                        in: fixture.root
                    )
                    .sorted()

                try Expect.equal(
                    names,
                    [
                        "FixtureApp",
                        "FixtureCLI",
                        "Worker",
                    ],
                    "executable targets are discovered from dump-package"
                )
            }

            Step("preserve detailed target classification") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let targets = try await TargetsDetailed.list(
                    in: fixture.root
                )

                let roles = Dictionary(
                    uniqueKeysWithValues: targets.map {
                        (
                            $0.name,
                            $0.role.rawValue
                        )
                    }
                )

                try Expect.equal(
                    roles["FixtureCLI"] ?? "",
                    "cli",
                    "CLI target is classified as cli"
                )

                try Expect.equal(
                    roles["FixtureApp"] ?? "",
                    "app",
                    "App target is classified as app"
                )

                try Expect.equal(
                    roles["Worker"] ?? "",
                    "other",
                    "unclassified executable remains other"
                )
            }

            Step("preserve explicit target paths") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let targets = try await TargetsDetailed.list(
                    in: fixture.root
                )

                let paths = Dictionary(
                    uniqueKeysWithValues: targets.map {
                        (
                            $0.name,
                            $0.path ?? ""
                        )
                    }
                )

                try Expect.equal(
                    paths["FixtureCLI"] ?? "",
                    "Sources/FixtureCLI",
                    "CLI target path survives dump-package decoding"
                )

                try Expect.equal(
                    paths["FixtureApp"] ?? "",
                    "Sources/FixtureApp",
                    "App target path survives dump-package decoding"
                )
            }
        }
    }
}
