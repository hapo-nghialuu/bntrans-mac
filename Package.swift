// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BNTransMac",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BNTransMac",
            path: "Sources/BNTransMac",
            resources: [.process("Resources")]
        )
    ]
)
