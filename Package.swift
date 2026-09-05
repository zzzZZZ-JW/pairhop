// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PairHop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "pairing-helper", targets: ["pairing-helper"])],
    targets: [
        .target(name: "PairingCore"),
        .executableTarget(name: "pairing-helper", dependencies: ["PairingCore"]),
        .testTarget(name: "PairingCoreTests", dependencies: ["PairingCore"])
    ],
    swiftLanguageModes: [.v5]
)
