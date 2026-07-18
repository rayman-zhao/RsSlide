// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RsSlide",
    platforms: [
    	.macOS(.v15),
    ],
    products: [
        .library(
            name: "RsSlide",
            targets: ["RsSlide"]),
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
                //.strictMemorySafety(true),
                .define("MORE_PROVIDERS_AVAILABLE"),
            ],
        ),
        .target(
            name: "CVendorSDKs",
            dependencies: [
            ],
            exclude: [
            ],
            sources: [
                "./Sources"
            ],
            cxxSettings: [
            ],
        ),
        .testTarget(
            name: "RsSlideTests",
            dependencies: ["RsSlide"],
            swiftSettings: [
                .define("MORE_PROVIDERS_AVAILABLE"),
            ],
        ),
    ]
)
