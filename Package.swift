// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Textractor",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Textractor", targets: ["Textractor"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Textractor",
            dependencies: [],
            path: "Sources/Textractor",
            exclude: [
                "Info.plist",
                "Resources/Textractor.entitlements",
                "Resources/Textractor.release.entitlements"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
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
            path: "Tests/TextractorTests"
        )
    ]
)

// Version: 2.0.0 - Release with multi-display OCR, Continuity Camera support, and webapp
