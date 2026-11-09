import Foundation

/// Capabilities that differ between the sandboxed App Store product and local
/// development builds. Stored preferences and existing bundle identifiers stay
/// compatible across distributions.
public enum DistributionPolicy {
    #if APP_STORE
    public static let isAppStoreBuild = true
    #else
    public static let isAppStoreBuild = false
    #endif

    public static let supportsAutomaticScrolling = !isAppStoreBuild
    public static let supportsGlobalPasteObservation = !isAppStoreBuild
}
