// swift-tools-version: 6.0
import PackageDescription

// AppCore — the platform-independent Swift core shared by every SwiftPort app.
// Rules enforced by `swiftport lint`:
//   * Foundation / Swift stdlib only. No SwiftUI, UIKit, AppKit, Combine,
//     or any other platform-locked framework.
//   * Public API types that must cross a bridge conform to `SwiftPortExported`.
let package = Package(
    name: "AppCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"])
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        )
    ]
)
