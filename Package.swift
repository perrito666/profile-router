// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProfileRouter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ProfileRouter", targets: ["ProfileRouter"])],
    targets: [
        .target(name: "RouterCore"),
        .executableTarget(name: "ProfileRouter", dependencies: ["RouterCore"]),
        .testTarget(name: "RouterCoreTests", dependencies: ["RouterCore"])
    ]
)
