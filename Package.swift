// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fkeysd",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FKeysCore"),
        .executableTarget(name: "fkeysd", dependencies: ["FKeysCore"]),
        .testTarget(name: "FKeysCoreTests", dependencies: ["FKeysCore"]),
    ]
)
