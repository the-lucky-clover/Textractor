#!/usr/bin/env swift
// Compatibility launcher for actual Textractor Pro XCTest screenshot attachments.
// Run: swift scripts/screenshot_runner.swift [--list|--test TEST_NAME]
// Debug UI attachments are QA evidence, not approved App Store screenshots.
import Foundation

let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("capture_screenshots_swift.sh")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [script.path] + Array(CommandLine.arguments.dropFirst())
do {
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
} catch {
    fputs("Could not run Textractor Pro screenshot tests: \(error)\n", stderr)
    exit(1)
}
