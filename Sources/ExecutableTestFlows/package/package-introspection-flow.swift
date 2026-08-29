import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var packageIntrospectionFlow: TestFlow {
        TestFlow(
            "package-introspection",
            tags: [
                "swiftpm",
                "manifest",
                "symbol-graph",
                "regression",
            ]
        ) {
            Step("manifest provides one shared package topology") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let manifest = try await Package.manifest(
                    at: fixture.root
                )

                try Expect.equal(
                    manifest.name,
                    "ExecutableFixture",
                    "manifest preserves package name"
                )

                try Expect.equal(
                    manifest.toolsVersion,
                    Optional("6.2.0"),
                    "manifest preserves Swift tools version"
                )

                try Expect.true(
                    manifest.products.contains {
                        $0.kind == .library
                            && $0.name == "FixtureCore"
                    },
                    "manifest retains library products"
                )

                try Expect.true(
                    manifest.targets.contains {
                        $0.type == "executable"
                            && $0.name == "FixtureCLI"
                    },
                    "manifest retains executable targets"
                )
            }

            Step("symbol graph dump returns compiler-produced graph files") {
                let fixture = try SwiftPackageFixture()

                defer {
                    fixture.remove()
                }

                let dump = try await Package.symbolGraphs(
                    at: fixture.root,
                    minimumAccessLevel: .public
                )

                try Expect.true(
                    !dump.files.isEmpty,
                    "symbol graph dump returns files"
                )

                try Expect.true(
                    dump.files.allSatisfy {
                        $0.lastPathComponent.hasSuffix(
                            ".symbols.json"
                        )
                    },
                    "symbol graph dump returns only symbol graph json"
                )
            }
        }
    }
}
