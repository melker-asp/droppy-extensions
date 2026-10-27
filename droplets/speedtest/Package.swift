// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Speedtest",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Speedtest", type: .dynamic, targets: ["Speedtest"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.20.1")
    ],
    targets: [
        .target(
            name: "Speedtest",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SpeedtestHarness",
            dependencies: [
                "Speedtest",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
