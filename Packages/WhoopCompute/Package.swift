// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoopCompute",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "WhoopCompute", targets: ["WhoopCompute"])],
    dependencies: [
        .package(path: "../WhoopStore"),
        .package(path: "../WhoopProtocol"),
    ],
    targets: [
        .target(
            name: "WhoopCompute",
            dependencies: ["WhoopStore", "WhoopProtocol"]
        ),
        .testTarget(
            name: "WhoopComputeTests",
            dependencies: ["WhoopCompute", "WhoopStore", "WhoopProtocol"]
        ),
    ]
)
