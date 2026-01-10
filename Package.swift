// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tunnels",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TunnelsApp", targets: ["TunnelsApp"])
    ],
    targets: [
        .executableTarget(
            name: "TunnelsApp",
            path: "Sources/TunnelsApp"
        )
    ]
)
