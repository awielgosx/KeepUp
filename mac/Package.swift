// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeepUp",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeepUp",
            path: "Sources/KeepUp"
        )
    ]
)
