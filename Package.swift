// swift-tools-version: 6.0
import PackageDescription

// The same Foundation-only sources are included by the app's Shared group.
// This package tests that boundary without an Apple UI or server SDK dependency.
let package = Package(
    name: "SwiftfinMediaServerCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v16), .tvOS(.v16)],
    products: [.library(name: "MediaServerCore", targets: ["MediaServerCore"])],
    targets: [
        .target(name: "MediaServerCore", path: "Shared/Services/MediaServers"),
        .target(name: "MediaServerAdapters", dependencies: ["MediaServerCore"], path: "Shared/Services/MediaServerAdapters"),
        .executableTarget(
            name: "SwiftfinNative",
            dependencies: ["MediaServerCore", "MediaServerAdapters"],
            path: "NativeMac/SwiftfinNative",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MediaServerAdapterTests",
            dependencies: ["MediaServerAdapters", "MediaServerCore"],
            path: "Tests/MediaServerAdapterTests"
        ),
        .testTarget(name: "MediaServerCoreTests", dependencies: ["MediaServerCore"], path: "Tests/MediaServerCoreTests"),
    ]
)
