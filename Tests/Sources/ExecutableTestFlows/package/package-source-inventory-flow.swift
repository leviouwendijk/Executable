import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var packageSourceInventoryFlow: TestFlow {
        TestFlow(
            "package-source-inventory",
            tags: [
                "swiftpm",
                "package",
                "sources",
                "targets",
                "regression",
            ]
        ) {
            Step(
                "SwiftPM reports exact target source membership"
            ) {
                let fixture = try SwiftPackageGraphFixture()

                defer {
                    fixture.remove()
                }

                let inventory = try await Package.sourceInventory(
                    at: fixture.root
                )

                try Expect.equal(
                    inventory.packageName,
                    "ExecutableGraphFixture",
                    "source inventory package name"
                )

                try Expect.equal(
                    inventory.targets
                        .map(\.name)
                        .sorted(),
                    [
                        "FixtureCLI",
                        "FixtureCore",
                    ],
                    "root package target inventory"
                )

                let core = try Expect.notNil(
                    inventory.target(
                        named: "FixtureCore"
                    ),
                    "FixtureCore source inventory"
                )

                try Expect.equal(
                    core.directory?.standardizedFileURL,
                    Optional(
                        fixture.root
                            .appendingPathComponent(
                                "Sources/FixtureCore"
                            )
                            .standardizedFileURL
                    ),
                    "FixtureCore resolved target directory"
                )

                try Expect.equal(
                    core.sourceFiles
                        .map(\.standardizedFileURL),
                    [
                        fixture.root
                            .appendingPathComponent(
                                "Sources/FixtureCore/FixtureCore.swift"
                            )
                            .standardizedFileURL,
                    ],
                    "FixtureCore exact source membership"
                )

                let cli = try Expect.notNil(
                    inventory.target(
                        named: "FixtureCLI"
                    ),
                    "FixtureCLI source inventory"
                )

                try Expect.equal(
                    cli.sourceFiles
                        .map(\.standardizedFileURL),
                    [
                        fixture.root
                            .appendingPathComponent(
                                "Sources/FixtureCLI/main.swift"
                            )
                            .standardizedFileURL,
                    ],
                    "FixtureCLI exact source membership"
                )
            }
        }
    }
}
