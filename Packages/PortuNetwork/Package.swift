// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuNetwork",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuNetwork", targets: ["PortuNetwork"])
    ],
    dependencies: [
        .package(path: "../PortuCore")
    ],
    targets: [
        .target(
            name: "PortuNetwork",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PortuNetworkTests",
            dependencies: ["PortuNetwork", "PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
