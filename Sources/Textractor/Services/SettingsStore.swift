import Foundation
import Combine
import AppKit

/// Persistent settings store backed by `UserDefaults`. Every change publishes
/// `objectWillChange` so any SwiftUI view refreshes automatically.
///
/// Persistence is debounced (~250 ms) so live widgets like the weirdness
/// slider can mutate settings continuously without thrashing `UserDefaults`.
@MainActor
public final class SettingsStore: ObservableObject {

    public static let shared = SettingsStore()
    public static let defaultsKey = "com.textractor.settings.v1"
    private static let onboardingKey = "com.textractor.onboardingCompleted"

    @Published public private(set) var current: AppSettings

    private let userDefaults: UserDefaults
    private var pendingPersist: DispatchWorkItem?

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.current = decoded
        } else {
            self.current = .default
        }
        applySideEffects(for: current)
    }

    // MARK: - Mutating

    public func update(_ settings: AppSettings) {
        self.current = settings
        applySideEffects(for: settings)
        schedulePersist(settings)
    }

    /// Convenience sugar.
    public func mutate(_ mutate: (inout AppSettings) -> Void) {
        var current = self.current
        mutate(&current)
        update(current)
    }

    /// One-call reset.
    public func resetToDefaults() {
        // Persist immediately for the reset path so the user is never one
        // tick away from an unflush.
        self.current = .default
        applySideEffects(for: .default)
        pendingPersist?.cancel()
        pendingPersist = nil
        if let data = try? JSONEncoder().encode(current) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Force any pending write to disk right now. Call from app termination so
    /// in-flight changes always land.
    public func flushPendingPersist() {
        guard let work = pendingPersist else { return }
        pendingPersist = nil
        work.perform()
    }

    // MARK: - Convenience computed ergonomic accessors

    public var weirdness: Double       { current.weirdness }
    public var fontScale: Double       { current.fontScale }

    // MARK: - Internals

    /// Apply cross-component side effects of the new settings (sounds, etc.).
private func applySideEffects(for settings: AppSettings) {
        SoundManager.enabled = settings.soundEffectsEnabled
        TelemetryService.shared.isEnabled = settings.localTelemetryEnabled
        // Push the user's chosen UI language into the global localization
        // lookup so T.s(_ key:) returns translated strings immediately.
        T.sharedLanguage.value = settings.uiLanguage
        // Apply dock presence changes (activation policy, status bar, etc.)
        applyDockPresence(settings.dockPresence)
        // Apply extended logging setting
        LoggerService.shared.setFileLoggingEnabled(settings.extendedLoggingEnabled)
    }
    
    /// Apply the dock presence setting by updating activation policy and status bar.
    private func applyDockPresence(_ presence: AppSettings.DockPresence) {
        let newPolicy: NSApplication.ActivationPolicy
        switch presence {
        case .menuBarOnly:
            newPolicy = .accessory
        case .dockOnly, .both:
            newPolicy = .regular
        }
        
        // Only change if different to avoid unnecessary UI flicker
        if NSApp.activationPolicy() != newPolicy {
            NSApp.setActivationPolicy(newPolicy)
        }
        
        // Notify AppCoordinator to show/hide status bar
        NotificationCenter.default.post(
            name: NSNotification.Name("DockPresenceChanged"),
            object: presence
        )
    }

    /// Coalesce rapid `update` calls so we only encode + write once per quiet
    /// window. Saves the most recent settings at flush time.
    private func schedulePersist(_ settings: AppSettings) {
        pendingPersist?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            self.userDefaults.set(data, forKey: Self.defaultsKey)
        }
        pendingPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Onboarding

    /// `true` once the user has either chosen an OCR language or explicitly
    /// skipped onboarding. Persists outside `AppSettings` so a factory reset
    /// doesn't bring the onboarding back.
    public var hasCompletedOnboarding: Bool {
        get { userDefaults.bool(forKey: Self.onboardingKey) }
        set { userDefaults.set(newValue, forKey: Self.onboardingKey) }
    }
}
