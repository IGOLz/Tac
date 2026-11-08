// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Tac", platforms: [.macOS(.v14)], dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")], targets: [
    .executableTarget(name: "Tac", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "TacTests", dependencies: ["Tac"])
])
