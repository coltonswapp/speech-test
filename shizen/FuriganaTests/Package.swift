// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FuriganaTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FuriganaReadingSplit"),
        .testTarget(
            name: "FuriganaReadingSplitTests",
            dependencies: ["FuriganaReadingSplit"]
        ),
    ]
)
