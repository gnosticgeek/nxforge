// swift-tools-version: 6.2
// NXForge Converter (formerly NxNative Converter): a SwiftUI app over scripts/build_ipa_from_nsp.py --platform mac-app (see README.md).
import PackageDescription

let package = Package(
    name: "NxNativeConverter",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "NxNativeConverter",
            path: "Sources/NxNativeConverter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ConverterTests",
            dependencies: ["NxNativeConverter"],
            path: "Tests/ConverterTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
