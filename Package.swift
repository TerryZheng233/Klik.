// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Klik",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Klik"),
        .testTarget(name: "KlikTests", dependencies: ["Klik"])
    ]
)
