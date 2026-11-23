// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wave",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Wave",
            path: "Sources/Wave",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
