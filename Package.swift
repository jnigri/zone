// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zone",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Zone",
            path: "Sources/Zone",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
