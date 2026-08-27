import Arguments
import Executable
import TestFlows

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
                    "modernize",
                    "version",
                    "remote",
                ] {
                    try Expect.true(
                        names.contains(name),
                        "sbm root contains \(name)"
                    )
                }
            }

            Step("increment parses native typed bump values") {
                let invocation = try Arguments.parse(
                    [
                        "increment",
                        "--target",
                        "release",
                        "minor",
                    ],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    try invocation.value(
                        "target",
                        as: SwiftVersionBumpTarget.self
                    ),
                    .release,
                    "increment target parses through ArgumentValue"
                )

                try Expect.equal(
                    try invocation.value(
                        "level",
                        as: SwiftVersionBumpLevel.self
                    ),
                    .minor,
                    "increment level parses through ArgumentValue"
                )
            }

            Step("remote subcommands resolve canonically") {
                let invocation = try Arguments.parse(
                    [
                        "remote",
                        "open",
                        "--branch",
                    ],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    invocation.commandPath.map(\.rawValue),
                    [
                        "sbm",
                        "remote",
                        "open",
                    ],
                    "remote open resolves canonical path"
                )
            }
        }
    }
}
