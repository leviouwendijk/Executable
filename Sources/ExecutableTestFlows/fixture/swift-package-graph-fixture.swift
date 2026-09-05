import Foundation

struct SwiftPackageGraphFixture {
    let root: URL

    init() throws {
        root = FileManager
            .default
            .temporaryDirectory
            .appendingPathComponent(
                "executable-package-graph-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        try writeLeafPackage()
        try writeMiddlePackage()
        try writeRootPackage()
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }
}

private extension SwiftPackageGraphFixture {
    func writeRootPackage() throws {
        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "ExecutableGraphFixture",
                products: [
                    .library(
                        name: "FixtureCore",
                        targets: [
                            "FixtureCore",
                        ]
                    ),
                    .executable(
                        name: "fixture-graph-cli",
                        targets: [
                            "FixtureCLI",
                        ]
                    ),
                ],
                dependencies: [
                    .package(
                        path: "Dependencies/FixtureMiddle"
                    ),
                ],
                targets: [
                    .target(
                        name: "FixtureCore"
                    ),
                    .executableTarget(
                        name: "FixtureCLI",
                        dependencies: [
                            .target(
                                name: "FixtureCore"
                            ),
                            .product(
                                name: "FixtureMiddle",
                                package: "FixtureMiddle"
                            ),
                        ]
                    ),
                ]
            )
            """,
            to: "Package.swift"
        )

        try write(
            """
            public struct FixtureCore {
                public init() {}
            }
            """,
            to: "Sources/FixtureCore/FixtureCore.swift"
        )

        try write(
            """
            import FixtureCore
            import FixtureMiddle

            _ = FixtureCore()
            _ = FixtureMiddle()
            """,
            to: "Sources/FixtureCLI/main.swift"
        )
    }

    func writeMiddlePackage() throws {
        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "FixtureMiddle",
                products: [
                    .library(
                        name: "FixtureMiddle",
                        targets: [
                            "FixtureMiddle",
                        ]
                    ),
                ],
                dependencies: [
                    .package(
                        path: "../FixtureLeaf"
                    ),
                ],
                targets: [
                    .target(
                        name: "FixtureMiddle",
                        dependencies: [
                            .product(
                                name: "FixtureLeaf",
                                package: "FixtureLeaf"
                            ),
                        ]
                    ),
                ]
            )
            """,
            to: "Dependencies/FixtureMiddle/Package.swift"
        )

        try write(
            """
            import FixtureLeaf

            public struct FixtureMiddle {
                public init() {
                    _ = FixtureLeaf()
                }
            }
            """,
            to: "Dependencies/FixtureMiddle/Sources/FixtureMiddle/FixtureMiddle.swift"
        )
    }

    func writeLeafPackage() throws {
        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "FixtureLeaf",
                products: [
                    .library(
                        name: "FixtureLeaf",
                        targets: [
                            "FixtureLeaf",
                        ]
                    ),
                ],
                targets: [
                    .target(
                        name: "FixtureLeaf"
                    ),
                ]
            )
            """,
            to: "Dependencies/FixtureLeaf/Package.swift"
        )

        try write(
            """
            public struct FixtureLeaf {
                public init() {}
            }
            """,
            to: "Dependencies/FixtureLeaf/Sources/FixtureLeaf/FixtureLeaf.swift"
        )
    }

    func write(
        _ contents: String,
        to path: String
    ) throws {
        let destination = root
            .appendingPathComponent(
                path
            )

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try contents.write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
    }
}
