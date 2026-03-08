// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OllamaBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OllamaBar",
            path: "Sources/OllamaBar",
            resources: [.process("Resources")]
        ),
    ]
)
