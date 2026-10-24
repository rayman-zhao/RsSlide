// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// MoreProviders is a private git submodule that public clones don't have; gate the
// flag on its presence so public checkouts build without manifest edits. SwiftPM
// caches manifest results (~/.swiftpm/cache/manifests) keyed by file content only,
// so checkouts sharing this identical file share one entry — clear that cache
// after flipping submodule presence if builds look stale.
let moreProvidersAvailable = FileManager.default.fileExists(
    atPath: "Sources/RsSlide/MoreProviders/MDS.swift")

let package = Package(
    name: "RsSlide",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "RsSlide",
            targets: ["RsSlide"])
    ],
    dependencies: [
        .package(url: "https://github.com/rayman-zhao/RsFoundation", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/RsPack", branch: "main"),
    ],
    targets: [
        .target(
            name: "RsSlide",
            dependencies: [
                .product(name: "RsFoundation", package: "RsFoundation"),
                .product(name: "RsPack", package: "RsPack"),
                "CVendorSDKs",
            ],
            swiftSettings: [
                // .strictMemorySafety(true),
            ] + (moreProvidersAvailable ? [.define("MORE_PROVIDERS_AVAILABLE")] : []),
        ),
        .target(
            name: "CVendorSDKs",
            dependencies: [],
            exclude: [],
            sources: [
                "./Sources"
            ],
            cxxSettings: [],
        ),
        .testTarget(
            name: "RsSlideTests",
            dependencies: ["RsSlide"],
            swiftSettings: moreProvidersAvailable ? [.define("MORE_PROVIDERS_AVAILABLE")] : [],
        ),
    ]
)
