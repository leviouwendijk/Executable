// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExecutableTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "t_executable", targets: ["ExecutableTests"]),
        .executable(name: "t_executable_frame", targets: ["ExecutableFrameTests"]),
        .executable(name: "t_executable_flows", targets: ["ExecutableTestFlows"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/leviouwendijk/Frame.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Testing.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/TestFlows.git", branch: "master"),
    ],
    targets: [
        .executableTarget(
            name: "ExecutableTests",
            dependencies: [
                .product(name: "Executable", package: "Executable"),
                .product(name: "Testing", package: "Testing"),
            ]
        ),
        .executableTarget(
            name: "ExecutableFrameTests",
            dependencies: [
                .product(name: "Executable", package: "Executable"),
                .product(name: "Frame", package: "Frame"),
                .product(name: "Testing", package: "Testing"),
            ]
        ),
        .executableTarget(
            name: "ExecutableTestFlows",
            dependencies: [
                .product(name: "Executable", package: "Executable"),
                .product(name: "TestFlows", package: "TestFlows"),
            ]
        ),
    ]
)
