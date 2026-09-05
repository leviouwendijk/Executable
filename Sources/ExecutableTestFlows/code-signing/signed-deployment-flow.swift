import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var signedDeploymentFlow: TestFlow {
        TestFlow(
            "signed-deployment",
            tags: ["codesign", "deploy", "macos", "swiftpm"]
        ) {
            Step("signed executable remains valid after canonical deployment") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                _ = try await Build.build(
                    at: fixture.root,
                    config: .init(mode: .debug, updateBuiltOnSuccess: false)
                )

                let destination = fixture.root.appendingPathComponent(
                    "signed-deployed",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: true
                )

                let request = SignedDeployment.Request(
                    project: fixture.root,
                    configuration: .debug,
                    product: "fixture-cli",
                    destination: destination,
                    signer: .adHoc,
                    identifier: "com.executable.signed-deployment-fixture"
                )
                let plan = try SignedDeployment.plan(request)
                let result = try await SignedDeployment.execute(plan)

                try Expect.true(
                    result.sourceSigning.verification.valid,
                    "built source verifies after signing"
                )
                try Expect.true(
                    result.deployedVerification.valid,
                    "deployed executable preserves a valid signature"
                )
                try Expect.equal(
                    result.deployedInspection.identifier,
                    Optional("com.executable.signed-deployment-fixture"),
                    "deployed executable preserves signing identifier"
                )
                try Expect.true(
                    result.deployedInspection.adHoc,
                    "deployed fixture preserves ad hoc signer classification"
                )
            }
        }
    }
}
