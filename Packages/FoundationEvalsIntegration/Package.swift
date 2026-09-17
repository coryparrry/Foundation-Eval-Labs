// swift-tools-version: 6.4

import Foundation
import PackageDescription

/// Apple's Evaluations framework ships in Xcode's developer library (next to XCTest),
/// not in the macOS SDK. Link that copy; do not vendor the binary.
let evaluationsFrameworkSearchPath: String = {
    let developerDir = Context.environment["DEVELOPER_DIR"]
        ?? "/Applications/Xcode.app/Contents/Developer"
    return "\(developerDir)/Platforms/MacOSX.platform/Developer/Library/Frameworks"
}()

let evaluationsSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-F", evaluationsFrameworkSearchPath]),
]

let evaluationsLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Evaluations"),
    .unsafeFlags([
        "-F", evaluationsFrameworkSearchPath,
        "-Xlinker", "-rpath",
        "-Xlinker", evaluationsFrameworkSearchPath,
    ]),
]

let package = Package(
    name: "FoundationEvalsIntegration",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(name: "FoundationEvalsIntegration", targets: ["FoundationEvalsIntegration"]),
        .library(name: "FoundationEvalsAppleBridge", targets: ["FoundationEvalsAppleBridge"]),
    ],
    targets: [
        .target(
            name: "FoundationEvalsIntegration"
        ),
        .target(
            name: "FoundationEvalsAppleBridge",
            dependencies: ["FoundationEvalsIntegration"],
            swiftSettings: evaluationsSwiftSettings,
            linkerSettings: evaluationsLinkerSettings
        ),
        .testTarget(
            name: "FoundationEvalsIntegrationTests",
            dependencies: ["FoundationEvalsIntegration"]
        ),
        .testTarget(
            name: "FoundationEvalsAppleBridgeTests",
            dependencies: ["FoundationEvalsAppleBridge", "FoundationEvalsIntegration"],
            swiftSettings: evaluationsSwiftSettings,
            linkerSettings: evaluationsLinkerSettings
        ),
    ]
)
