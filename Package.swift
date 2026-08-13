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
        .executable(
            name: "etest",
            targets: ["ExecutableTestFlows"]
        ),
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
            ]
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
