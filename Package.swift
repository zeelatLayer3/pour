// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pour",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pour",
            path: "Sources/Pour",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
