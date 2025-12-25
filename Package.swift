// swift-tools-version: 6.2
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
        .package(url: "https://github.com/rayman-zhao/RsHelper.git", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/RsPack.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "RsSlide",
            dependencies: [
                .product(name: "RsHelper", package: "RsHelper"),
                .product(name: "RsPack", package: "RsPack"),
            ],
            swiftSettings: [
                //.strictMemorySafety(true),
                //.define("MORE_PROVIDERS_AVAILABLE"),
            ],
        ),
        .testTarget(
            name: "RsSlideTests",
            dependencies: ["RsSlide"],
            swiftSettings: [
                //.define("MORE_PROVIDERS_AVAILABLE"),
            ],
        ),
    ]
)
