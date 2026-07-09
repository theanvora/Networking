// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "AnvyxNetworkKit", targets: ["AnvyxNetworkKit"]),
    ],
    targets: [
        .target(name: "AnvyxNetworkKit"),
        .testTarget(name: "AnvyxNetworkKitTests", dependencies: ["AnvyxNetworkKit"]),
    ]
)
