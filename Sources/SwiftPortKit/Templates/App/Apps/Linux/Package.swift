// swift-tools-version: 6.0
import PackageDescription

// LinuxApp — GTK4 + Libadwaita interface following the GNOME HIG.
// Requires system packages: gtk4, libadwaita-1 (pkg-config detectable).
//   Debian/Ubuntu: sudo apt install libgtk-4-dev libadwaita-1-dev
//   Fedora:        sudo dnf install gtk4-devel libadwaita-devel
//   macOS (optional local builds): brew install gtk4 libadwaita
let package = Package(
    name: "__APP_MODULE__Linux",
    dependencies: [
        .package(path: "../../Core"),
        .package(url: "https://git.aparoksha.dev/aparoksha/adwaita-swift", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "__APP_MODULE__",
            dependencies: [
                .product(name: "AppCore", package: "Core"),
                .product(name: "Adwaita", package: "adwaita-swift"),
            ]
        ),
        .testTarget(
            name: "ContractTests",
            dependencies: [
                .product(name: "AppCore", package: "Core"),
            ]
        )
    ]
)
