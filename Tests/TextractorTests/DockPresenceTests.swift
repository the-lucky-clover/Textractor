import AppKit
import XCTest
@testable import Textractor

@MainActor
final class DockPresenceTests: XCTestCase {
    func testDockOnlyRelaunchRestoresDockAndCaptureControlsAfterBootstrap() throws {
        let suite = "com.textractor.test.dock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
        store.mutate { $0.dockPresence = .dockOnly }
        store.flushPendingPersist()
        let restored = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)

        var activationPolicy = NSApplication.ActivationPolicy.accessory
        var events: [String] = []
        let delegate = AppDelegate(lifecycle: .init(
            dockPresence: { restored.current.dockPresence },
            setActivationPolicy: { activationPolicy = $0 },
            activate: { events.append("activate") },
            bootstrap: { events.append("bootstrap") },
            presentInterface: { events.append("capture controls") },
            showsLaunchSplash: false
        ))
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(activationPolicy, .regular, "Dock-only launch must not hide the sole app entry point.")
        XCTAssertEqual(events, ["activate", "bootstrap", "capture controls"])
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testOtherLaunchModesDoNotOpenAnUnrequestedDockWindow() throws {
        for presence in [AppSettings.DockPresence.menuBarOnly, .both] {
            let suite = "com.textractor.test.dock.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)
            store.mutate { $0.dockPresence = presence }
            store.flushPendingPersist()
            let restored = SettingsStore(userDefaults: defaults, appliesSystemEffects: false)

            var appliedPolicy: NSApplication.ActivationPolicy?
            var bootstrapped = false
            var openedWindow = false
            let delegate = AppDelegate(lifecycle: .init(
                dockPresence: { restored.current.dockPresence },
                setActivationPolicy: { appliedPolicy = $0 },
                activate: {},
                bootstrap: { bootstrapped = true },
                presentInterface: { openedWindow = true },
                showsLaunchSplash: false
            ))
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

            XCTAssertEqual(appliedPolicy, presence == .menuBarOnly ? .accessory : .regular)
            XCTAssertTrue(bootstrapped)
            XCTAssertFalse(openedWindow)
        }
    }

    func testDockClickReopensClosedControlsWithoutReplacingAVisibleWindow() {
        var presentations = 0
        let delegate = AppDelegate(lifecycle: .init(
            dockPresence: { .dockOnly },
            setActivationPolicy: { _ in },
            activate: {},
            bootstrap: {},
            presentInterface: { presentations += 1 },
            showsLaunchSplash: false
        ))

        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        XCTAssertEqual(presentations, 0, "An open settings/history window should retain normal AppKit activation.")
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertEqual(presentations, 1, "Closing the last window must not make Dock-only capture controls unreachable.")
    }
}
