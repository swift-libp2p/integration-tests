// swift-tools-version: 6.0
//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "integration-tests",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "IntegrationTests",
            targets: ["IntegrationTests"]
        )
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/swift-libp2p/swift-libp2p.git", .upToNextMinor(from: "0.3.0")),

        // Test Dependencies
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-yamux.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-mplex.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-noise.git", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swift-libp2p/swift-libp2p-plaintext.git", .upToNextMinor(from: "0.2.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "IntegrationTests"
        ),
        .testTarget(
            name: "IntegrationTestsTests",
            dependencies: [
                "IntegrationTests",
                .product(name: "LibP2P", package: "swift-libp2p"),
                .product(name: "LibP2PTesting", package: "swift-libp2p"),

                .product(name: "LibP2PYAMUX", package: "swift-libp2p-yamux"),
                .product(name: "LibP2PMPLEX", package: "swift-libp2p-mplex"),

                .product(name: "LibP2PNoise", package: "swift-libp2p-noise"),
                .product(name: "LibP2PPlaintext", package: "swift-libp2p-plaintext"),

            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
