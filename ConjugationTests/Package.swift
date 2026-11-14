// swift-tools-version: 6.0
import PackageDescription

// Unit tests for naming a tapped verb/adjective form (聞きました → polite past of 聞く).
// Sources/ConjugationForm/ConjugationForm.swift is a symlink to
// shizen/Dictionary/ConjugationForm.swift, so these tests run against the shipped file.
let package = Package(
    name: "ConjugationTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ConjugationForm"),
        .testTarget(
            name: "ConjugationFormTests",
            dependencies: ["ConjugationForm"]
        ),
    ]
)
