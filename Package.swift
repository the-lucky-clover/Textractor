// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Textractor",
    defaultLocalization: "en-US",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Textractor", targets: ["Textractor"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Textractor",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/Textractor",
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Vision"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftData"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "TextractorTests",
            dependencies: ["Textractor"],
            path: "Tests/TextractorTests",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

// Version: 2.0.0 - Release with multi-display OCR, Continuity Camera support, and webapp
