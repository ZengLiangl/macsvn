// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macsvn",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SvnCore", targets: ["SvnCore"])
    ],
    targets: [
        .target(name: "SvnCore", path: "Sources/SvnCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["SvnCore"], path: "Tests/CoreChecks")
    ]
)
