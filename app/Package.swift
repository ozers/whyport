// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WhyPort",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WhyPortCore", path: "Sources/WhyPortCore"),
        .executableTarget(
            name: "WhyPort",
            dependencies: ["WhyPortCore"],
            path: "Sources/WhyPort"
        ),
        .executableTarget(
            name: "WhyPortChecks",
            dependencies: ["WhyPortCore"],
            path: "Checks"
        ),
    ]
)
