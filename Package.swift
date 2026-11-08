// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Tac", platforms: [.macOS(.v14)], targets: [
    .executableTarget(name: "Tac"),
    .testTarget(name: "TacTests", dependencies: ["Tac"])
])
