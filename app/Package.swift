// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AIUsageCore"),
        .executableTarget(name: "AIUsageBar", dependencies: ["AIUsageCore"]),
        .testTarget(name: "AIUsageCoreTests", dependencies: ["AIUsageCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
