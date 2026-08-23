// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InteractionKit",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "InteractionKit", targets: ["InteractionKit"]),
    ],
    targets: [
        .target(
            name: "InteractionKit",
            dependencies: []
        ),
    ]
)
