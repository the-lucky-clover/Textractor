// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Textractor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Textractor", targets: ["Textractor"])
    ],
    targets: [
        .executableTarget(
            name: "Textractor",
            path: "Sources/Textractor",
            exclude: [
                "Info.plist",
                "Resources"
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
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)

// Version: 2.0.0 - Release with multi-display OCR, Continuity Camera support, and webapp
