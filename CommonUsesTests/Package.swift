// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommonUsesTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CommonUsesGatewayPayload"),
        .testTarget(
            name: "CommonUsesGatewayPayloadTests",
            dependencies: ["CommonUsesGatewayPayload"]
        ),
    ]
)
