// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GondarCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GondarCore", targets: ["GondarCore"]),
    ],
    targets: [
        // The rules the app follows. Foundation only.
        .target(name: "GondarCore"),
        .testTarget(name: "GondarCoreTests", dependencies: ["GondarCore"], resources: [.copy("Fixtures")]),
    ]
)
