// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NNotch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NNotch",
            path: "Sources/NNotch"
        )
    ]
)
