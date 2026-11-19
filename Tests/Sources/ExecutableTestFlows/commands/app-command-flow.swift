import Arguments
import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var appCommandFlow: TestFlow {
        TestFlow(
            "app-command",
            tags: [
                "arguments",
                "sbm",
                "app",
            ]
        ) {
            Step("complete sbm root command inventory is native") {
                let names = try SwiftBuildManagerCommand.spec()
                    .children
                    .map {
                        $0.name.rawValue
                    }

                try Expect.equal(
                    names,
                    [
                        "app",
                        "x",
                        "build",
                        "lib",
                        "renew-repositories",
                        "kill-swiftpm",
                        "remove",
                        "list",
                        "setup",
                        "clean",
                        "pack",
                        "config",
                        "increment",
                        "update",
                        "modernize",
                        "version",
                        "remote",
                    ],
                    "native sbm command inventory matches the legacy root"
                )
            }

            Step("package name discovery is reusable Executable API") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                try Expect.equal(
                    try await Package.name(
                        at: fixture.root
                    ),
                    "ExecutableFixture",
                    "Package.name reads SwiftPM package identity"
                )
            }

            Step("app execution plan preserves launch semantics") {
                let info = AppBundleInfo(
                    appBundleURL: URL(
                        fileURLWithPath: "/tmp/Fixture.app",
                        isDirectory: true
                    ),
                    bundleIdentifier: "com.example.fixture",
                    executableName: "Fixture"
                )

                let plan = AppBundleExecution.plan(
                    info,
                    mode: .open(
                        newInstance: true
                    ),
                    arguments: [
                        "one",
                        "two",
                    ]
                )

                try Expect.equal(
                    plan.executable.path,
                    "/usr/bin/open",
                    "open launch uses system open"
                )

                try Expect.equal(
                    plan.arguments,
                    [
                        "-n",
                        "/tmp/Fixture.app",
                        "--args",
                        "one",
                        "two",
                    ],
                    "open launch plan preserves app arguments"
                )
            }
        }
    }
}
