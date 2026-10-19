// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Marginalia",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Marginalia", targets: ["MarginaliaApp"]),
        .executable(name: "md", targets: ["md"]),
        .library(name: "MarginaliaCore", targets: ["MarginaliaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "MarginaliaCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: [.unsafeFlags(["-Onone"], .when(configuration: .debug))]
        ),
        .executableTarget(
            name: "MarginaliaApp",
            dependencies: ["MarginaliaCore"],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "md",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .testTarget(name: "MarginaliaCoreTests", dependencies: ["MarginaliaCore"]),
    ]
)
