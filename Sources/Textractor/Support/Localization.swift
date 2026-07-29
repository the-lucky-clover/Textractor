import Foundation
import SwiftUI

public struct Localization: Sendable, Equatable, Identifiable {
    public let id: String
    public let code: String
    public let displayName: String

    public init(_ code: String, displayName: String) {
        self.id = code
        self.code = code
        self.displayName = displayName
    }

    public static let catalog: [Localization] = [
        Localization("en-US", displayName: "English"),
        Localization("en-GB", displayName: "English (UK)"),
        Localization("es-ES", displayName: "Español"),
        Localization("fr-FR", displayName: "Français"),
        Localization("de-DE", displayName: "Deutsch"),
        Localization("it-IT", displayName: "Italiano"),
        Localization("pt-BR", displayName: "Português (BR)"),
        Localization("nl-NL", displayName: "Nederlands"),
        Localization("ru-RU", displayName: "Русский"),
        Localization("ja-JP", displayName: "日本語"),
        Localization("ko-KR", displayName: "한국어"),
        Localization("zh-Hans", displayName: "中文（简）"),
        Localization("zh-Hant", displayName: "中文（繁）"),
        Localization("ar-SA", displayName: "العربية"),
    ]

    public static func code(for displayName: String) -> String? {
        catalog.first { $0.displayName == displayName }?.code
    }

    public static func displayName(for code: String) -> String {
        catalog.first { $0.code == code }?.displayName ?? code
    }

    public static func isSupported(_ code: String) -> Bool {
        catalog.contains { $0.code == code }
    }
}

public struct T: Sendable, Equatable {
    public let code: String

    public init(_ code: String) {
        self.code = code
    }

    /// Thread-safe shared source for "current" language used by the static
    /// `T.s(_ key:)` lookup. `SettingsStore.applySideEffects` updates this
    /// whenever the user picks a new language in Settings, so the user's
    /// preference always wins over `Locale.current`. Falls back to
    /// `Locale.current` only when the user has never made a choice (empty
    /// string).
    public static let sharedLanguage = SharedBox(initial: "")

    public func s(_ key: String, args: CVarArg...) -> String {
        Self.lookup(code: code, key: key, args: args)
    }

    public static func s(_ key: String, args: CVarArg...) -> String {
        let code = sharedLanguage.value
        if code.isEmpty {
            return lookup(code: "", key: key, args: args)
        }
        return lookup(code: code, key: key, args: args)
    }

    public static func s(_ code: String, _ key: String, args: CVarArg...) -> String {
        lookup(code: code, key: key, args: args)
    }

    // MARK: - .strings-backed lookup (production)

    private static func stringsBundle(for language: String) -> Bundle? {
        // Production: .lproj directories are in Bundle.main/Contents/Resources
        if let lprojPath = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: lprojPath) {
            return bundle
        }
        // Development: SPM may place resources in Bundle.module
        if #available(macOS 13, *),
           let lprojURL = Bundle.module.url(forResource: language, withExtension: "lproj") {
            return Bundle(url: lprojURL)
        }
        return nil
    }

    private static func lookupStrings(for language: String, key: String) -> String? {
        guard let bundle = stringsBundle(for: language) else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        if value == key || value.isEmpty { return nil }
        return value
    }

    private static func lookup(code: String, key: String, args: [CVarArg]) -> String {
        let actualCode = code.isEmpty ? Locale.current.identifier : code
        let locale = Locale(identifier: actualCode)
        let language = locale.language.languageCode?.identifier ?? "en"

        // 1. Try the user's language from .strings files
        var format = lookupStrings(for: language, key: key)

        // 2. Fallback to English from .strings files
        if format == nil && language != "en" {
            format = lookupStrings(for: "en", key: key)
        }

        let result = format ?? key
        if args.isEmpty { return result }
        return String(format: result, arguments: args)
    }
}

public final class SharedBox: @unchecked Sendable {
    private var _value: String
    private let lock = NSLock()
    init(initial: String) { self._value = initial }
    var value: String {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
