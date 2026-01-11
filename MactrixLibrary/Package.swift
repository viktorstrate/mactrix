// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MactrixLibrary",
    platforms: [.macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UI",
            targets: ["UI"]
        ),
        .library(
            name: "Models",
            targets: ["Models"]
        ),
        .library(name: "Utils", targets: ["Utils"]),
    ],
    /* dependencies: [
            .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", from: "25.10.27"),
        ], */
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UI",
            dependencies: ["Models"]
        ),
        .target(name: "Utils"),
        .testTarget(name: "UtilsTests", dependencies: ["Utils"]),
        /* .target(
                name: "TimelineUI",
                dependencies: ["Models", .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")]
            ), */
        .target(
            name: "Models"
        ),
    ]
)
