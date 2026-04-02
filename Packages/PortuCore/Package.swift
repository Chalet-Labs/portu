// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuCore", targets: ["PortuCore"])
    ],
    targets: [
        .target(
            name: "PortuCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PortuCoreTests",
            dependencies: ["PortuCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
