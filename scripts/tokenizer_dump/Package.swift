// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tokenizer_dump",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/shinjukunian/Mecab-Swift", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "tokenizer_dump",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Mecab-Swift", package: "mecab-swift"),
                .product(name: "IPADic", package: "mecab-swift"),
            ],
        ),
    ]
)
