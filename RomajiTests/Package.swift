// swift-tools-version: 6.0
import PackageDescription

// Unit tests for the app's kana → romaji conversion.
// Sources/KanaRomanizer/KanaRomanizer.swift is a symlink to shizen/Kana/KanaRomanizer.swift,
// so these tests run against the exact file the app ships.
let package = Package(
    name: "RomajiTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KanaRomanizer"),
        .testTarget(
            name: "KanaRomanizerTests",
            dependencies: ["KanaRomanizer"]
        ),
    ]
)
