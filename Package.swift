// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "maconary",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "maconary", targets: ["maconary"])],
    targets: [.executableTarget(name: "maconary")]
)
