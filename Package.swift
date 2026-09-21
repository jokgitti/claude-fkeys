// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fkeysd",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FKeysCore"),
        .executableTarget(name: "fkeysd", dependencies: ["FKeysCore"]),
        .testTarget(name: "FKeysCoreTests", dependencies: ["FKeysCore"]),
    ]
)
