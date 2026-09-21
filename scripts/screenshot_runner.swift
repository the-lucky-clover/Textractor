#!/usr/bin/env swift
// screenshot_runner.swift
// Standalone Swift script to capture App Store screenshots
// Run with: swift run screenshot_runner.swift
// Or compile: swiftc screenshot_runner.swift -o capture_screenshots && ./capture_screenshots

import Foundation
import AppKit
import ApplicationServices

// Configuration
let outputDir = URL(fileURLWithPath: "dist/screenshots", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
let bundleID = "com.textractor.app"
let targetSize = CGSize(width: 1280, height: 800)

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

struct Scene {
    let name: String
    let setup: () -> Bool
    let captureWindowTitle: String?
}

// Global reference to the app
var targetApp: NSRunningApplication?

func launchApp() -> Bool {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    if let app = apps.first {
        targetApp = app
        app.activate()
        return true
    }
    
    let url = URL(fileURLWithPath: "/Applications/Textractor.app")
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        if let error = error {
            print("❌ Failed to launch: \(error)")
        } else {
            targetApp = app
        }
    }
    
    // Wait for launch
    for _ in 0..<30 {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil {
            targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            return true
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    return false
}

func findWindow(titleContains: String) -> AXUIElement? {
    guard let app = targetApp else { return nil }
    let pid = app.processIdentifier
    let appRef = AXUIElementCreateApplication(pid)
    
    var windows: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windows)
    guard result == .success, let windowArray = windows as? [AXUIElement] else { return nil }
    
    for window in windowArray {
        var title: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
           let titleStr = title as? String,
           titleStr.localizedCaseInsensitiveContains(titleContains) {
            return window
        }
    }
    return nil
}

func resizeWindow(_ window: AXUIElement, to size: CGSize, at origin: CGPoint = CGPoint(x: 100, y: 100)) {
    var newSize = size
    var newOrigin = origin
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &newSize)!)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &newOrigin)!)
}

func captureWindow(_ window: AXUIElement, to url: URL) -> Bool {
    var imageRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(window, "AXSnapshot" as CFString, &imageRef)
    guard result == .success, let cgImage = imageRef as? CGImage else {
        // Fallback: use screencapture
        return false
    }
    
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return false }
    try? pngData.write(to: url)
    return true
}

func captureScreenRegion(_ rect: CGRect, to url: URL) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-R", "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))", url.path]
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
}

func clickMenuItem(_ menuTitle: String, _ itemTitle: String) -> Bool {
    // Use AppleScript for menu clicks
    let script = """
    tell application "System Events"
        tell process "Textractor"
            click menu item "\(itemTitle)" of menu "\(menuTitle)" of menu bar 1
        end tell
    end tell
    """
    var error: NSDictionary?
    let appleScript = NSAppleScript(source: script)
    appleScript?.executeAndReturnError(&error)
    return error == nil
}

func pressKey(keyCode: Int, modifiers: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
    keyDown?.flags = modifiers
    keyUp?.flags = modifiers
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

// ============================================================
// SCENE DEFINITIONS
// ============================================================

let scenes: [Scene] = [
    Scene(
        name: "01-capture-overlay",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Capture", "Capture Region")
            Thread.sleep(forTimeInterval: 1.5)
            return true
        },
        captureWindowTitle: "Capture Overlay"
    ),
    Scene(
        name: "02-window-capture",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Capture", "Capture Window")
            Thread.sleep(forTimeInterval: 0.5)
            // Press SPACE to switch to window mode
            pressKey(keyCode: 49) // SPACE
            Thread.sleep(forTimeInterval: 1)
            return true
        },
        captureWindowTitle: "Window Picker"
    ),
    Scene(
        name: "03-history-grid",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Window", "History")
            Thread.sleep(forTimeInterval: 1.5)
            // Resize window
            if let window = findWindow(titleContains: "History") {
                resizeWindow(window, to: targetSize)
            }
            Thread.sleep(forTimeInterval: 1)
            return true
        },
        captureWindowTitle: "History"
    ),
    Scene(
        name: "04-source-code-mode",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Textractor", "Settings...")
            Thread.sleep(forTimeInterval: 1.5)
            // Note: Would need more specific UI interaction for toggles
            return true
        },
        captureWindowTitle: "Settings"
    ),
    Scene(
        name: "05-translation-settings",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Textractor", "Settings...")
            Thread.sleep(forTimeInterval: 1.5)
            return true
        },
        captureWindowTitle: "Settings"
    ),
    Scene(
        name: "06-toast-actions",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Capture", "Capture Region")
            Thread.sleep(forTimeInterval: 1.5)
            // Do a small capture
            pressKey(keyCode: 0) // A key to start drag? This is complex
            Thread.sleep(forTimeInterval: 3) // Wait for toast
            return true
        },
        captureWindowTitle: nil // Toast is a separate window
    ),
    Scene(
        name: "07-pii-redaction",
        setup: {
            guard launchApp() else { return false }
            Thread.sleep(forTimeInterval: 1)
            _ = clickMenuItem("Textractor", "Settings...")
            Thread.sleep(forTimeInterval: 1.5)
            return true
        },
        captureWindowTitle: "Settings"
    )
]

// ============================================================
// MAIN
// ============================================================

print("🎬 Textractor Screenshot Automation")
print("   Output: \(outputDir.path)")
print("   Target size: \(Int(targetSize.width))x\(Int(targetSize.height))")
print("")

guard launchApp() else {
    print("❌ Failed to launch Textractor")
    exit(1)
}

print("✅ App launched (PID: \(targetApp?.processIdentifier ?? 0))")
print("")

for scene in scenes {
    print("📸 Setting up: \(scene.name)")
    
    if scene.setup() {
        print("   ✅ Setup complete")
        
        // Find and capture window
        if let windowTitle = scene.captureWindowTitle,
           let window = findWindow(titleContains: windowTitle) {
            let url = outputDir.appendingPathComponent("\(scene.name).png")
            if captureWindow(window, to: url) {
                print("   📸 Captured via AXSnapshot: \(url.lastPathComponent)")
            } else if captureScreenRegion(CGRect(x: 100, y: 100, width: targetSize.width, height: targetSize.height), to: url) {
                print("   📸 Captured via screencapture: \(url.lastPathComponent)")
            } else {
                print("   ❌ Capture failed")
            }
        } else {
            // Fallback: capture screen region
            let url = outputDir.appendingPathComponent("\(scene.name).png")
            if captureScreenRegion(CGRect(x: 100, y: 100, width: targetSize.width, height: targetSize.height), to: url) {
                print("   📸 Captured screen region: \(url.lastPathComponent)")
            }
        }
    } else {
        print("   ❌ Setup failed")
    }
    
    print("")
}

print("🎉 Done! Screenshots in: \(outputDir.path)")
print("")
print("Next steps:")
print("  1. Review screenshots in \(outputDir.path)")
print("  2. Crop/adjust in Preview if needed")
print("  3. Upload to App Store Connect")