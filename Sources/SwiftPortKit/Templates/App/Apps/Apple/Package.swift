// swift-tools-version: 6.0
import PackageDescription

// AppleApp — SwiftUI interface layer + verification tooling.
// `AppUI` is consumed by both the Xcode app targets (macOS + iOS) and the
// `snapshot-runner` executable used by `swiftport verify --snapshots`.
let package = Package(
    name: "__APP_MODULE__Apple",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"])
    ],
    dependencies: [
        .package(path: "../../Core")
    ],
    targets: [
        .target(
            name: "AppUI",
            dependencies: [.product(name: "AppCore", package: "Core")]
        ),
        .executableTarget(
            name: "snapshot-runner",
            dependencies: [
                "AppUI",
                .product(name: "AppCore", package: "Core"),
            ]
        ),
        .testTarget(
            name: "ContractTests",
            dependencies: [
                "AppUI",
                .product(name: "AppCore", package: "Core"),
            ]
        )
    ]
)
