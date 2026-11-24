// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPort",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "swiftport", targets: ["swiftport"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "SwiftPortKit",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
            resources: [.copy("Templates")]
        ),
        .executableTarget(
            name: "swiftport",
            dependencies: [
                "SwiftPortKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "SwiftPortKitTests",
            dependencies: ["SwiftPortKit"]
        )
    ]
)
