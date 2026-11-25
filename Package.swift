// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QCYKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QCYKit", targets: ["QCYKit"])],
    targets: [
        .target(name: "QCYKit"),
        .testTarget(name: "QCYKitTests", dependencies: ["QCYKit"], resources: [.process("Fixtures")])
    ]
)
