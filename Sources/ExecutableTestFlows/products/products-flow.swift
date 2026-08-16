import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var productsFlow: TestFlow {
        TestFlow(
            "products",
            tags: [
                "swiftpm",
                "products",
                "executables",
                "regression",
            ]
        ) {
            Step(
                "distinguish executable products from executable targets"
            ) {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let targets = try await Targets
                    .executableNames(
                        in: fixture.root
                    )
                    .sorted()

                try Expect.true(
                    targets.contains(
                        "FixtureCLI"
                    ),
                    "target discovery retains FixtureCLI module name"
                )

                try Expect.false(
                    targets.contains(
                        "fixture-cli"
                    ),
                    "product name is not confused with target name"
                )

                let products = try await Products
                    .executables(
                        in: fixture.root
                    )

                guard let cli = products.first(
                    where: {
                        $0.name == "fixture-cli"
                    }
                ) else {
                    throw ProductsFlowError.missingFixtureCLIProduct
                }

                try Expect.equal(
                    cli.targets,
                    [
                        "FixtureCLI",
                    ],
                    "executable product retains target mapping"
                )

                try Expect.false(
                    products.contains {
                        $0.name == "FixtureCLI"
                    },
                    "target name is not exposed as executable product name"
                )
            }

            Step(
                "whole package build emits executable product name"
            ) {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                _ = try await Build.build(
                    at: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    )
                )

                let productBinary = fixture.root
                    .appendingPathComponent(
                        ".build/debug/fixture-cli"
                    )

                let targetNamedBinary = fixture.root
                    .appendingPathComponent(
                        ".build/debug/FixtureCLI"
                    )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: productBinary.path
                    ),
                    "SwiftPM emits executable using product name"
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: targetNamedBinary.path
                    ),
                    "SwiftPM does not emit executable using differing target name"
                )
            }

            Step(
                "selected deployment uses executable product name"
            ) {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                _ = try await Build.build(
                    at: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    )
                )

                let destination = fixture.root
                    .appendingPathComponent(
                        "deployed",
                        isDirectory: true
                    )

                try Deploy.selected(
                    from: fixture.root,
                    config: .init(
                        mode: .debug,
                        updateBuiltOnSuccess: false
                    ),
                    to: destination,
                    products: [
                        "fixture-cli",
                    ]
                )

                let deployed = destination
                    .appendingPathComponent(
                        "fixture-cli"
                    )

                let metadata = destination
                    .appendingPathComponent(
                        "fixture-cli.metadata"
                    )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: deployed.path
                    ),
                    "deployment uses executable product name"
                )

                try Expect.true(
                    FileManager.default.fileExists(
                        atPath: metadata.path
                    ),
                    "deployment metadata uses executable product name"
                )

                try Expect.false(
                    FileManager.default.fileExists(
                        atPath: destination
                            .appendingPathComponent(
                                "FixtureCLI"
                            )
                            .path
                    ),
                    "deployment does not use target name as binary name"
                )
            }
        }
    }
}

private enum ProductsFlowError:
    Error
{
    case missingFixtureCLIProduct
}
