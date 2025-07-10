// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UpYNABSync",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "up-ynab-sync",
            targets: ["UpYNABSync"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "UpYNABSync",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift")
            ]
        ),
        .testTarget(
            name: "UpYNABSyncTests",
            dependencies: ["UpYNABSync"]
        )
    ]
)
