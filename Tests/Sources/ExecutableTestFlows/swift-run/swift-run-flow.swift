import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var swiftRunFlow: TestFlow {
        TestFlow(
            "swift-run",
            tags: [
                "process",
                "swiftpm",
                "execution",
                "regression",
            ]
        ) {
            Step(
                "run discovered executable product"
            ) {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let result = try await SwiftRun.run(
                    .init(
                        product: "fixture-cli"
                    ),
                    at: fixture.root
                )

                try Expect.true(
                    result.isSuccess,
                    "discovered executable product runs successfully"
                )

                try Expect.equal(
                    result.exitCode ?? -1,
                    Int32(0),
                    "successful executable product preserves zero exit code"
                )

                try Expect.equal(
                    result.product,
                    "fixture-cli",
                    "result preserves requested product identity"
                )
            }

            Step(
                "reject unknown executable product before launch"
            ) {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                var rejected = false

                do {
                    _ = try await SwiftRun.run(
                        .init(
                            product:
                                "definitely-missing-product"
                        ),
                        at: fixture.root
                    )
                } catch SwiftRunError.productNotFound(
                    let product,
                    let available
                ) {
                    rejected =
                        product
                            == "definitely-missing-product"
                        && available.contains(
                            "fixture-cli"
                        )
                }

                try Expect.true(
                    rejected,
                    "unknown executable product is rejected against typed product discovery"
                )
            }
        }
    }
}
