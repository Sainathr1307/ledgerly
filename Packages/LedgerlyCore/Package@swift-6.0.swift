// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LedgerlyCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "LedgerlyCore", targets: ["LedgerlyCore"])
    ],
    targets: [
        .target(name: "LedgerlyCore"),
        .testTarget(name: "LedgerlyCoreTests", dependencies: ["LedgerlyCore"])
    ],
    swiftLanguageModes: [.v6]
)
