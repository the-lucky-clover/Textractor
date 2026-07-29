import Foundation

/// Counts the number of times the app has launched since inception. Each
/// `applicationDidFinishLaunching` increments the counter and persists it, so
/// the running build's "build N" reflects how many builds/sessions the user
/// has progressed through rather than a static CFBundleVersion.
public final class BuildCounter {

    public static let shared = BuildCounter()

    private let key = "com.textractor.buildCountSinceInception"
    private let userDefaults: UserDefaults

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The persisted count of launches since inception.
    public var count: Int {
        userDefaults.integer(forKey: key)
    }

    /// Increment the counter for this launch and return the new value. Call once
    /// per app launch (idempotent within a single launch).
    @discardableResult
    public func increment() -> Int {
        let next = count + 1
        userDefaults.set(next, forKey: key)
        return next
    }
}
