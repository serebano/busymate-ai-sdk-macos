// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BusymateAI",
    platforms: [.macOS(.v12)],
    products: [.library(name: "BusymateAI", targets: ["BusymateAI"])],
    targets: [
        .target(name: "BusymateAI"),
        .testTarget(name: "BusymateAITests", dependencies: ["BusymateAI"]),
    ],
    swiftLanguageVersions: [.v5]
)
