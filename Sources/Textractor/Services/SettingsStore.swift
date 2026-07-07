import Foundation
import Combine

/// Persistent settings store backed by `UserDefaults`.  Every change publishes
/// `objectWillChange` so any SwiftUI view refreshes automatically.
public final class SettingsStore: ObservableObject {

    public static let defaultsKey = "com.textractor.settings.v1"

    @Published public private(set) var current: AppSettings

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.current = decoded
        } else {
            self.current = .default
        }
    }

    // MARK: - Mutating

    public func update(_ settings: AppSettings) {
        self.current = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Convenience sugar.
    public func mutate(_ mutate: (inout AppSettings) -> Void) {
        var current = self.current
        mutate(&current)
        update(current)
    }

    /// One-call reset.
    public func resetToDefaults() {
        update(.default)
    }

    // MARK: - Convenience computed ergonomic accessors

    public var storageMode: StorageMode { current.storageMode }
    public var weirdness: Double       { current.weirdness }
    public var autoPasteEnabled: Bool  { current.autoPasteEnabled }
    public var quickShareTargets: Set<QuickShareTarget> { current.quickShareTargets }
    public var festiveFeedback: Bool   { current.festiveFeedback }
}

