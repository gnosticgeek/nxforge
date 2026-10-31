// swift-tools-version: 6.2
// NXForge Converter: a SwiftUI app over scripts/build_ipa_from_nsp.py --platform mac-app (see README.md).
import PackageDescription

let package = Package(
    name: "NXForgeConverter",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "NXForgeConverter",
            path: "Sources/NXForgeConverter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ConverterTests",
            dependencies: ["NXForgeConverter"],
            path: "Tests/ConverterTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
