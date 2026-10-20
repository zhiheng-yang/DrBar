// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DrBarKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DrBarKit", targets: ["DrBarKit"]),
        .library(name: "CCFDDLKit", targets: ["CCFDDLKit"]),
        .library(name: "DrBarUI", targets: ["DrBarUI"]),
    ],
    dependencies: [
        // The only third-party dependency. Stay on the current major version.
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")
    ],
    targets: [
        .target(name: "DrBarKit"),
        .target(
            name: "CCFDDLKit",
            dependencies: ["DrBarKit", .product(name: "Yams", package: "Yams")]
        ),
        .target(
            name: "DrBarUI",
            dependencies: ["DrBarKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DrBarKitTests",
            dependencies: ["DrBarKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CCFDDLKitTests",
            dependencies: ["CCFDDLKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DrBarUITests", dependencies: ["DrBarUI"]),
    ]
)
