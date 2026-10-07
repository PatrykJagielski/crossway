// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Crossway",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Crossway", path: "Sources/Crossway", exclude: ["Resources"])
    ]
)
