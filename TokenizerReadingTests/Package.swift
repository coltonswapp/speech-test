// swift-tools-version: 6.0
import PackageDescription

// MeCab + JMdict reading tests. Sources are symlinks to the files the app ships.
let package = Package(
    name: "TokenizerReadingTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "TokenizerReading",
            dependencies: [
                .product(name: "IPADic", package: "Mecab-Swift"),
                .product(name: "Mecab-Swift", package: "Mecab-Swift"),
                .product(name: "StringTools", package: "Mecab-Swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "TokenizerReadingTests",
            dependencies: ["TokenizerReading"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
