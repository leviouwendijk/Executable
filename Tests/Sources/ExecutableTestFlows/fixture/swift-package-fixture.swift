import Foundation

struct SwiftPackageFixture {
    let root: URL

    init() throws {
        root = FileManager
            .default
            .temporaryDirectory
            .appendingPathComponent(
                "executable-fixture-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        try writePackage()
    }

    func remove() {
        try? FileManager.default.removeItem(
            at: root
        )
    }

    func breakCLICompilation() throws {
        let source = root
            .appendingPathComponent(
                "Sources/FixtureCLI/main.swift"
            )

        try """
        import FixtureCore

        this is deliberately invalid swift
        """.write(
            to: source,
            atomically: true,
            encoding: .utf8
        )
    }
}

extension SwiftPackageFixture {
    /// A nested `Tests/` package with one product, `t_fixture`, depending on the fixture by path,
    /// described by `tests` (package.frame source). With `throughSibling`, a second package also
    /// depends on the fixture, as a test library whose graph contains the package under test would.
    func writeTestPackage(
        tests: String = "import Executable;\n\nlet tests: Tests = .{};\n",
        throughSibling: Bool = false
    ) throws {
        let parent = root.lastPathComponent
        let middleDependency = throughSibling ? #", .package(path: "Middle")"# : ""
        let middleProduct = throughSibling ? #", .product(name: "Middle", package: "Middle")"# : ""

        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "ExecutableFixtureTests",
                products: [
                    .executable(name: "t_fixture", targets: ["FixtureTests"]),
                ],
                dependencies: [.package(path: "..")\(middleDependency)],
                targets: [
                    .executableTarget(
                        name: "FixtureTests",
                        dependencies: [.product(name: "FixtureCore", package: "\(parent)")\(middleProduct)]
                    ),
                ]
            )
            """,
            to: "Tests/Package.swift"
        )

        try write(
            """
            import FixtureCore

            print("tests-\\(fixtureValue())")
            """,
            to: "Tests/Sources/FixtureTests/main.swift"
        )

        try write(tests, to: "Tests/package.frame")

        guard throughSibling else { return }

        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "Middle",
                products: [.library(name: "Middle", targets: ["Middle"])],
                dependencies: [.package(path: "../..")],
                targets: [
                    .target(
                        name: "Middle",
                        dependencies: [.product(name: "FixtureCore", package: "\(parent)")]
                    ),
                ]
            )
            """,
            to: "Tests/Middle/Package.swift"
        )

        try write(
            """
            import FixtureCore

            public func middleValue() -> String { fixtureValue() }
            """,
            to: "Tests/Middle/Sources/Middle/middle.swift"
        )
    }
}

private extension SwiftPackageFixture {
    func writePackage() throws {
        try write(
            """
            // swift-tools-version: 6.2

            import PackageDescription

            let package = Package(
                name: "ExecutableFixture",
                products: [
                    .library(
                        name: "FixtureCore",
                        targets: ["FixtureCore"]
                    ),
                    .executable(
                        name: "fixture-cli",
                        targets: ["FixtureCLI"]
                    ),
                    .executable(
                        name: "FixtureApp",
                        targets: ["FixtureApp"]
                    ),
                ],
                targets: [
                    .target(
                        name: "FixtureCore",
                        path: "Sources/FixtureCore"
                    ),
                    .executableTarget(
                        name: "FixtureCLI",
                        dependencies: ["FixtureCore"],
                        path: "Sources/FixtureCLI"
                    ),
                    .executableTarget(
                        name: "FixtureApp",
                        dependencies: ["FixtureCore"],
                        path: "Sources/FixtureApp"
                    ),
                    .executableTarget(
                        name: "Worker",
                        dependencies: ["FixtureCore"],
                        path: "Sources/Worker"
                    ),
                ]
            )
            """,
            to: "Package.swift"
        )

        try write(
            """
            public func fixtureValue() -> String {
                "fixture"
            }
            """,
            to: "Sources/FixtureCore/core.swift"
        )

        try write(
            """
            import FixtureCore

            print("cli-\\(fixtureValue())")
            """,
            to: "Sources/FixtureCLI/main.swift"
        )

        try write(
            """
            import FixtureCore

            print("app-\\(fixtureValue())")
            """,
            to: "Sources/FixtureApp/main.swift"
        )

        try write(
            """
            import FixtureCore

            print("worker-\\(fixtureValue())")
            """,
            to: "Sources/Worker/main.swift"
        )
    }

    func write(
        _ contents: String,
        to relativePath: String
    ) throws {
        let destination = root
            .appendingPathComponent(
                relativePath
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
