// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Klik",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Klik", resources: [.process("Localization")]),
        .testTarget(name: "KlikTests", dependencies: ["Klik"])
    ]
)
