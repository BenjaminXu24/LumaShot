// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LumaShot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumaShot", targets: ["LumaShot"])],
    targets: [
        .executableTarget(name: "LumaShot", path: "Sources/LumaShot", linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
            .linkedFramework("ScreenCaptureKit"), .linkedFramework("Carbon"),
            .linkedFramework("Vision")
        ]),
        .testTarget(name: "LumaShotTests", dependencies: ["LumaShot"], path: "Tests/LumaShotTests")
    ],
    swiftLanguageVersions: [.v5]
)
