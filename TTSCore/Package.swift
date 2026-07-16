// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TTSCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TTSCore", targets: ["TTSCore"]),
    ],
    targets: [
        .target(
            name: "TTSCore",
            dependencies: []
        ),
    ]
)
