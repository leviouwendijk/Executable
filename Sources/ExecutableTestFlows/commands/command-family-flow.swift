import Arguments
import Executable
import TestFlows

extension ExecutableFlowSuite {
    static var commandFamilyFlow: TestFlow {
        TestFlow(
            "command-family",
            tags: [
                "arguments",
                "sbm",
                "commands",
            ]
        ) {
            Step("compile and deployment command family is registered") {
                let spec = try SwiftBuildManagerCommand.spec()
                let names = spec.children.map {
                    $0.name.rawValue
                }

                for name in [
                    "lib",
                    "kill-swiftpm",
                    "renew-repositories",
                    "remove",
                    "list",
                    "setup",
                ] {
                    try Expect.true(
                        names.contains(name),
                        "sbm root contains \(name)"
                    )
                }
            }

            Step("kill aliases resolve canonically") {
                let invocation = try Arguments.parse(
                    [
                        "kill",
                        "--dry-run",
                    ],
                    spec: try SwiftBuildManagerCommand.spec()
                )

                try Expect.equal(
                    invocation.commandPath.map(\.rawValue),
                    [
                        "sbm",
                        "kill-swiftpm",
                    ],
                    "kill alias resolves to canonical command path"
                )
            }

            Step("library command rejects contradictory modes") {
                let exit = await SwiftBuildManagerCommand.run(
                    arguments: [
                        "lib",
                        "--release",
                        "--debug",
                    ]
                )

                try Expect.true(
                    exit != 0,
                    "lib rejects simultaneous debug and release modes"
                )
            }
        }
    }
}
