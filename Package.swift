// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JNotch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "JNotch",
            path: "Sources/JNotch"
        )
    ]
)
