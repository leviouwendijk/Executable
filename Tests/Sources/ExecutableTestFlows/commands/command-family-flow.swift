import Arguments
@_spi(Testing) import Executable
import ExecutableLegacy
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

            Step("embedded workflow docs dispatch without shadowing native help") {
                let spec = try SwiftBuildManagerCommand.spec()
                let names = spec.children.map(\.name.rawValue)
                try Expect.true(names.contains("docs"), "docs command is registered")
                try Expect.false(names.contains("help"), "native help is not shadowed")

                let invocation = try Arguments.parse(
                    ["docs", "workflows"],
                    spec: spec
                )
                try Expect.equal(
                    invocation.commandPath.map(\.rawValue),
                    ["sbm", "docs", "workflows"],
                    "docs workflow topic resolves through normal command parsing"
                )

                for arguments in [
                    ["docs", "workflows"],
                    ["help", "wf"],
                    ["wf", "run", "--help"],
                ] {
                    let exit = await SwiftBuildManagerMigrationCommand.run(arguments: arguments)
                    try Expect.equal(
                        exit,
                        Int32(0),
                        "CLI dispatch succeeds: \(arguments.joined(separator: " "))"
                    )
                }

                for phrase in [
                    ".sbm/workflows.pkl",
                    "--execute",
                    "--publish",
                    "--message",
                    "dependency_stale",
                    "needs",
                ] {
                    try Expect.true(
                        SwiftDocsWorkflowsCommand.reference.contains(phrase),
                        "embedded workflow docs contain \(phrase)"
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

            Step("-t and -b run tests and benchmarks without overriding package.frame") {
                let spec = try SwiftBuildManagerMigrationCommand.spec()

                let bare = try Arguments.parse(["-t", "-b"], spec: spec)
                try Expect.equal(bare.commandPath.map(\.rawValue), ["sbm", "build"], "sbm -t -b is the default build")
                let options = try bare.options(SwiftBuildCommand.Options.self)
                try Expect.true(options.test && options.bench, "-t is test, -b is bench on build")
                try Expect.false(SwiftBuildCommand.hasExplicitInput(bare), "-t/-b keep the package.frame build")

                let debug = try Arguments.parse(["build", "-t", "-d"], spec: spec)
                try Expect.true(SwiftBuildCommand.hasExplicitInput(debug), "a build flag still overrides package.frame")

                let pack = try Arguments.parse(["pack", "-b", "-t", "--bench"], spec: spec)
                try Expect.equal(pack.commandPath.map(\.rawValue), ["sbm", "pack", "get"], "pack flags reach pack get")
                let packOptions = try pack.options(SwiftPackGetCommand.Options.self)
                try Expect.true(packOptions.build && packOptions.test && packOptions.bench, "-b is build on pack; --bench is long only")
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
