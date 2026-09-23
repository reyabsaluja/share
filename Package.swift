// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "share-cli",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "share",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ShareCLI"
        ),
        .testTarget(
            name: "ShareCLITests",
            dependencies: ["share"],
            path: "Tests/ShareCLITests"
        ),
    ]
)
