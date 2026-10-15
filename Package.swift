// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dictionary",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "dictionary", targets: ["dictionary"])],
    targets: [.executableTarget(name: "dictionary")]
)
