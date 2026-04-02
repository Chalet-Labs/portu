// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PortuUI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PortuUI", targets: ["PortuUI"])
    ],
    targets: [
        .target(
            name: "PortuUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "PortuUITests",
            dependencies: ["PortuUI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
