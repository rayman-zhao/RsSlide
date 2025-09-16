// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RsSlide",
    products: [
        .library(
            name: "RsSlide",
            targets: ["RsSlide"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rayman-zhao/RsHelper.git", branch: "main"),
        .package(url: "https://github.com/rayman-zhao/RsPack.git", branch: "main"),
        .package(url: "https://github.com/patricktcoakley/Winnie.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "RsSlide",
            dependencies: [
                .product(name: "RsHelper", package: "RsHelper"),
                .product(name: "RsPack", package: "RsPack"),
                .product(name: "Winnie", package: "Winnie"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                //.strictMemorySafety(true),
                //.define("MORE_PROVIDERS_AVAILABLE"),
            ],
        ),
        .testTarget(
            name: "RsSlideTests",
            dependencies: ["RsSlide"],
            swiftSettings: [.interoperabilityMode(.Cxx)],
        ),
    ]
)
