// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "NativeHA",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "NativeHACore",
            targets: ["NativeHACore"]
        ),
        .executable(
            name: "ha-probe",
            targets: ["HAProbe"]
        ),
        .executable(
            name: "NativeHAMac",
            targets: ["NativeHAMac"]
        ),
        .executable(
            name: "GraphBench",
            targets: ["GraphBench"]
        ),
        .executable(
            name: "GraphPyramidBench",
            targets: ["GraphPyramidBench"]
        ),
    ],
    targets: [
        .target(
            name: "NativeHACore"
        ),
        .executableTarget(
            name: "HAProbe",
            dependencies: ["NativeHACore"]
        ),
        .executableTarget(
            name: "NativeHAMac",
            dependencies: ["NativeHACore"]
        ),
        .executableTarget(
            name: "GraphBench",
            dependencies: ["NativeHACore"]
        ),
        .executableTarget(
            name: "GraphPyramidBench",
            dependencies: ["NativeHACore"]
        ),
        .testTarget(
            name: "NativeHACoreTests",
            dependencies: ["NativeHACore"]
        ),
        .testTarget(
            name: "NativeHAMacTests",
            dependencies: ["NativeHAMac"],
            exclude: ["ReferenceImages"]
        ),
    ]
)
