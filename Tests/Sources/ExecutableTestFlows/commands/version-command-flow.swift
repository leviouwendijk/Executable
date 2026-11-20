import Arguments
import Executable
import ExecutableLegacy
import TestFlows
import Version

extension ExecutableFlowSuite {
    static var versionCommandFlow: TestFlow {
        TestFlow(
            "version-command",
            tags: [
                "arguments",
                "sbm",
                "version",
            ]
        ) {
            Step("version command family is registered") {
                let names = try SwiftBuildManagerCommand.spec()
                    .children
                    .map {
                        $0.name.rawValue
                    }

                for name in [
                    "config",
                    "increment",
                    "update",
                    "version",
                ] {
                    try Expect.true(
                        names.contains(name),
                        "sbm root contains \(name)"
                    )
                }
                try Expect.false(names.contains("modernize"), "core sbm has no legacy migration")
                try Expect.false(names.contains("remote"), "the pkl update URL command is gone")

                let migration = try SwiftBuildManagerMigrationCommand.spec()
                    .children
                    .map {
                        $0.name.rawValue
                    }
                try Expect.equal(migration, names + ["wf", "pkg", "modernize"], "the migration root adds the Pkl commands to core")
            }

            Step("increment parses native typed bump values") {
                let invocation = try Arguments.parse(
                    [
                        "increment",
                        "minor",
                    ],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    try invocation.value(
                        "level",
                        as: ObjectVersionLevel.self
                    ),
                    .minor,
                    "increment level parses through ArgumentValue"
                )
            }
        }
    }
}
