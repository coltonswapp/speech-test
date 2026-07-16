// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GrammarContentKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GrammarContentKit", targets: ["GrammarContentKit"]),
        .executable(name: "merge-grammar-content", targets: ["merge-grammar-content"]),
    ],
    targets: [
        .target(
            name: "GrammarContentKit",
            dependencies: []
        ),
        .executableTarget(
            name: "merge-grammar-content",
            dependencies: ["GrammarContentKit"]
        ),
    ]
)
