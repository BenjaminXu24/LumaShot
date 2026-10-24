// swift-tools-version: 5.9
import PackageDescription

// Translation.framework ships with macOS 15+. Weak-link it so a Mac on the
// macOS 14 deployment target can still launch. A normal import would autolink
// a hard dependency and fail dyld on macOS 14.
let weakTranslationLink: [LinkerSetting] = [
    .unsafeFlags(
        ["-Xlinker", "-weak_framework", "-Xlinker", "Translation"],
        .when(platforms: [.macOS])
    )
]
let disableTranslationAutolink: [SwiftSetting] = [
    .unsafeFlags(
        ["-disable-autolink-framework", "Translation"],
        .when(platforms: [.macOS])
    )
]

let package = Package(
    name: "LumaShot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumaShot", targets: ["LumaShot"])],
    targets: [
        .executableTarget(
            name: "LumaShot",
            path: "Sources/LumaShot",
            swiftSettings: disableTranslationAutolink,
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"), .linkedFramework("Carbon"),
                .linkedFramework("Vision")
            ] + weakTranslationLink
        ),
        .testTarget(
            name: "LumaShotTests",
            dependencies: ["LumaShot"],
            path: "Tests/LumaShotTests",
            linkerSettings: weakTranslationLink
        )
    ],
    swiftLanguageVersions: [.v5]
)
