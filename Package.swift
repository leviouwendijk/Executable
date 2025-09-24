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
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/plate.git", // ansi and things
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Structures.git", // JSONValue
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Interfaces.git", // JSONValue
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "Executable",
            dependencies: [
                .product(name: "plate", package: "plate"),
                .product(name: "Structures", package: "Structures"),
                .product(name: "Interfaces", package: "Interfaces"),
            ],
        ),
        .testTarget(
            name: "ExecutableTests",
            dependencies: [
                "Executable",
                .product(name: "plate", package: "plate"),
                .product(name: "Structures", package: "Structures"),
                .product(name: "Interfaces", package: "Interfaces"),
            ]
        ),
    ]
)
