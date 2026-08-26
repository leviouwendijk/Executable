import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var buildWorkflowFlow: TestFlow {
        TestFlow(
            "build-workflow",
            tags: [
                "swiftpm",
                "build",
                "arguments",
                "resolution",
            ]
        ) {
            Step("native build command lowers explicit arguments") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let request = try SwiftBuildCommand.request(
                    arguments: [
                        "--debug",
                        "--local",
                        "--products",
                        "fixture-cli",
                    ],
                    defaultProject: fixture.root,
                    updateBuiltOnSuccess: false
                )

                try Expect.equal(
                    request.config.buildDirComponent,
                    "debug",
                    "explicit debug option lowers into Build.Config"
                )

                try Expect.false(
                    request.deploy,
                    "local build suppresses deployment"
                )

                let plan = try await Build.resolve(
                    request
                )

                try Expect.equal(
                    plan.selectedProductNames,
                    [
                        "fixture-cli",
                    ],
                    "explicit product selection resolves through reusable Build plan"
                )
            }

            Step("build-object defaults lower into the same typed request") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let buildObject = fixture.root.appendingPathComponent(
                    "build-object.pkl"
                )

                try """
                uuid = "00000000-0000-0000-0000-000000000001"
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

                let request = try SwiftBuildCommand.projectDefaultRequest(
                    from: fixture.root,
                    updateBuiltOnSuccess: false
                )

                try Expect.equal(
                    request.config.buildDirComponent,
                    "debug",
                    "build-object debug option lowers into Build.Config"
                )

                try Expect.false(
                    request.deploy,
                    "build-object local option suppresses deployment"
                )

                switch request.source {
                case .buildObject(let url, let arguments):
                    try Expect.equal(
                        url,
                        buildObject,
                        "build request retains build-object source identity"
                    )

                    try Expect.equal(
                        arguments,
                        [
                            "--debug",
                            "--local",
                            "--products",
                            "fixture-cli",
                        ],
                        "build request retains build-object audit arguments"
                    )

                case .direct:
                    throw BuildWorkflowFlowError.expectedBuildObjectSource
                }

                let plan = try await Build.resolve(
                    request
                )

                try Expect.equal(
                    plan.selectedProductNames,
                    [
                        "fixture-cli",
                    ],
                    "build-object defaults use the same reusable product resolver"
                )
            }

            Step("unknown product validation is a Build domain error") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let request = Build.Request(
                    project: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    ),
                    deploy: false,
                    selection: .init(
                        products: [
                            "missing-product",
                        ]
                    )
                )

                do {
                    _ = try await Build.resolve(
                        request
                    )

                    throw BuildWorkflowFlowError.expectedResolutionFailure
                } catch Build.ResolutionError.unknownProducts(let names) {
                    try Expect.equal(
                        names,
                        [
                            "missing-product",
                        ],
                        "unknown product is surfaced by Build resolution"
                    )
                }
            }
        }
    }
}

private enum BuildWorkflowFlowError: Error {
    case expectedBuildObjectSource
    case expectedResolutionFailure
}
