// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftCodeContext",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "codecontext", targets: ["CodeContext"])
    ],
    dependencies: [
        // Apple's native CLI argument parser
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "CodeContext",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CodeContext"
        ),
        .testTarget(
            name: "CodeContextTests",
            dependencies: ["CodeContext"],
            path: "Tests/CodeContextTests"
        ),
    ]
)
