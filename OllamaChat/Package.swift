// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OllamaChat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OllamaChat",
            path: "Sources/OllamaChat"
        ),
        .testTarget(
            name: "OllamaChatTests",
            dependencies: ["OllamaChat"],
            path: "Tests/OllamaChatTests"
        ),
    ]
)
