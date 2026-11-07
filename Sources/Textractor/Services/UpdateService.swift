import AppKit
import Foundation

public struct ReleaseVersion: Comparable, Equatable {
    public let components: [Int]
    public init?(_ raw: String) {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public enum ReleaseCheck: Equatable {
    case noPublishedRelease, current(String), available(String)
    static func parse(status: Int, data: Data, installed: String) throws -> Self {
        if status == 404 { return .noPublishedRelease }
        guard status == 200 else { throw NSError(domain: "UpdateCheck", code: status, userInfo: [NSLocalizedDescriptionKey: "The release service returned HTTP \(status). Try again later."]) }
        struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease,
              let remote = ReleaseVersion(release.tag_name), let local = ReleaseVersion(installed) else {
            throw NSError(domain: "UpdateCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Release metadata could not be compared with this build."])
        }
        return remote > local ? .available(release.tag_name) : .current(release.tag_name)
    }
}

@MainActor
public final class UpdateService {
    public static let shared = UpdateService()
    private var checking = false
    private init() {}
    public static var bundleShortVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    public static var bundleVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    public static var versionDescription: String { "v\(bundleShortVersion) (build \(bundleVersion))" }
    public static let hasRemoteChannel = true
    private static let releasePage = URL(string: "https://github.com/the-lucky-clover/Textractor/releases")!

    /// Checks on explicit user action. Opens the release page only after the user chooses it.
    public func presentUpToDateAlert() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            let alert = NSAlert()
            alert.alertStyle = .informational
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/the-lucky-clover/Textractor/releases/latest")!)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, data.count <= 1_000_000 else { throw URLError(.badServerResponse) }
                let result = try ReleaseCheck.parse(status: response.statusCode, data: data, installed: Self.bundleShortVersion)
                SettingsStore.shared.mutate { $0.lastUpdateCheckAt = Date() }
                switch result {
                case .noPublishedRelease:
                    alert.messageText = "No published release yet"
                    alert.informativeText = "Installed: \(Self.versionDescription). This repository has no stable published release to compare."
                case .current(let latest):
                    alert.messageText = "No newer stable release"
                    alert.informativeText = "Installed: \(Self.versionDescription). Latest published release: \(latest)."
                case .available(let latest):
                    alert.messageText = "Textractor Pro \(latest) is available"
                    alert.informativeText = "Installed: \(Self.versionDescription). Review the release notes and download options on GitHub."
                    alert.addButton(withTitle: "View release")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Self.releasePage) }
                    return
                }
            } catch {
                alert.messageText = "Could not check for updates"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
            }
            alert.runModal()
        }
    }
    public static func relativeLastChecked(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
