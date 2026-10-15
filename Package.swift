// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Executable",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Executable",
            targets: ["Executable"]
        ),

        // lengthy testing
        .executable(
            name: "etest",
            targets: ["ExecutableTestFlows"]
        ),

        // fast test suite
        .executable(name: "t_executable", targets: ["ExecutableTests"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/plate.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Interfaces.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Terminal.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Indentation.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Path.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Primitives.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Version.git",
            branch: "master"
        ),
        .package(url: "https://github.com/leviouwendijk/Parsers.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Testing.git", branch: "master"),
        .package(
            url: "https://github.com/leviouwendijk/Arguments.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Processes.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "Executable",
            dependencies: [
                .product(name: "plate", package: "plate"),
                .product(name: "Interfaces", package: "Interfaces"),
                .product(name: "Processes", package: "Processes"),
                .product(name: "Terminal", package: "Terminal"),
                .product(name: "Indentation", package: "Indentation"),
                .product(name: "Path", package: "Path"),
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Version", package: "Version"),
                .product(name: "Parsers", package: "Parsers"),
                .product(name: "Arguments", package: "Arguments"),
            ]
        ),
        .executableTarget(
            name: "ExecutableTests",
            dependencies: [
                "Executable",
                .product(name: "Testing", package: "Testing"),
            ],
            path: "Testing/ExecutableTests"
        ),
        .executableTarget(
            name: "ExecutableTestFlows",
            dependencies: [
                "Executable",
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ]
)
