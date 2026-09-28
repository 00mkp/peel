// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "peel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "peel", targets: ["peel"]),
        .library(name: "ConvertKit", targets: ["ConvertKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "ConvertKit"),
        .target(
            name: "PeelCLI",
            dependencies: [
                "ConvertKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .executableTarget(name: "peel", dependencies: ["PeelCLI"]),
        .target(name: "TestSupport", dependencies: ["ConvertKit"], path: "Tests/TestSupport"),
        .testTarget(name: "ConvertKitTests", dependencies: ["ConvertKit", "TestSupport"]),
        .testTarget(name: "PeelCLITests", dependencies: ["PeelCLI", "ConvertKit", "TestSupport"]),
    ],
    swiftLanguageModes: [.v5]
)
