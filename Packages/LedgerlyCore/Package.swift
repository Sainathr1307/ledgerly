// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LedgerlyCore",
    platforms: [.iOS("18.0"), .macOS("14.0")],
    products: [
        .library(name: "LedgerlyCore", targets: ["LedgerlyCore"])
    ],
    targets: [
        .target(
            name: "LedgerlyCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "LedgerlyCoreTests",
            dependencies: ["LedgerlyCore"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
