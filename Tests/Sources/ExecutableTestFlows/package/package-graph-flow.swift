import Executable
import Foundation
import TestFlows

extension ExecutableFlowSuite {
    static var packageGraphFlow: TestFlow {
        TestFlow(
            "package-graph",
            tags: [
                "swiftpm",
                "manifest",
                "dependencies",
                "graph",
                "regression",
            ]
        ) {
            Step(
                "manifest retains declared package and target dependencies"
            ) {
                let fixture = try SwiftPackageGraphFixture()

                defer {
                    fixture.remove()
                }

                let manifest = try await Package.manifest(
                    at: fixture.root
                )

                try Expect.equal(
                    manifest.name,
                    "ExecutableGraphFixture",
                    "manifest package name"
                )

                try Expect.equal(
                    manifest.dependencies.count,
                    1,
                    "manifest package dependency count"
                )

                try Expect.equal(
                    manifest.dependencies.first?.kind,
                    Optional(
                        SwiftPackageManifest
                            .Dependency
                            .Kind
                            .fileSystem
                    ),
                    "local path dependency kind"
                )

                let cli = try Expect.notNil(
                    manifest.targets.first {
                        $0.name == "FixtureCLI"
                    },
                    "FixtureCLI target"
                )

                let dependencies = cli.dependencies
                    .map { dependency in
                        [
                            dependency.kind.rawValue,
                            dependency.name,
                            dependency.package ?? "-",
                        ]
                            .joined(
                                separator: ":"
                            )
                    }
                    .sorted()

                try Expect.equal(
                    dependencies,
                    [
                        "product:FixtureMiddle:FixtureMiddle",
                        "target:FixtureCore:-",
                    ],
                    "target dependency kinds remain explicit"
                )
            }

            Step(
                "graph resolves deterministic transitive package topology"
            ) {
                let fixture = try SwiftPackageGraphFixture()

                defer {
                    fixture.remove()
                }

                let graph = try await Package.graph(
                    at: fixture.root
                )

                try Expect.equal(
                    graph.manifest.name,
                    "ExecutableGraphFixture",
                    "graph retains root manifest"
                )

                try Expect.equal(
                    graph.packages.count,
                    3,
                    "resolved graph package count"
                )

                try Expect.equal(
                    graph.packages
                        .map(\.name)
                        .sorted(),
                    [
                        "ExecutableGraphFixture",
                        "FixtureLeaf",
                        "FixtureMiddle",
                    ],
                    "resolved graph package names"
                )

                let namesByIdentity = Dictionary(
                    uniqueKeysWithValues:
                        graph.packages.map {
                            (
                                $0.identity,
                                $0.name
                            )
                        }
                )

                let edges = graph.edges
                    .compactMap { edge -> String? in
                        guard
                            let source = namesByIdentity[
                                edge.sourceIdentity
                            ],
                            let target = namesByIdentity[
                                edge.targetIdentity
                            ]
                        else {
                            return nil
                        }

                        return source
                            + "->"
                            + target
                    }
                    .sorted()

                try Expect.equal(
                    edges,
                    [
                        "ExecutableGraphFixture->FixtureMiddle",
                        "FixtureMiddle->FixtureLeaf",
                    ],
                    "resolved transitive package edges"
                )

                try Expect.equal(
                    graph.rootPackage?.name,
                    Optional(
                        "ExecutableGraphFixture"
                    ),
                    "root identity resolves root package"
                )
            }
        }
    }
}
