// swift-tools-version: 6.0
import PackageDescription

// The same Foundation-only sources are included by the app's Shared group.
// This package tests that boundary without an Apple UI or server SDK dependency.
let package = Package(
    name: "SwiftfinMediaServerCore",
    platforms: [.macOS(.v15), .iOS(.v16), .tvOS(.v16)],
    products: [.library(name: "MediaServerCore", targets: ["MediaServerCore"])],
    targets: [
        .target(name: "MediaServerCore", path: "Shared/Services/MediaServers"),
        .testTarget(name: "MediaServerCoreTests", dependencies: ["MediaServerCore"], path: "Tests/MediaServerCoreTests"),
    ]
)
