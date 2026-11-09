import Foundation

struct AdditiveClipboardPersistence {
    let url: URL
    static var defaultURL: URL {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["TEXTRACTOR_UI_TEST_SUITE"], suite.hasPrefix("com.textractor.uitest.") {
            return FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("batch.json")
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Textractor/AdditiveClipboard.json")
    }
    func load() throws -> CaptureAccumulator {
        guard FileManager.default.fileExists(atPath: url.path) else { return CaptureAccumulator() }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 8_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let entries = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        var result = CaptureAccumulator()
        for entry in entries {
            guard result.append(entry) else { throw CocoaError(.fileReadCorruptFile) }
        }
        return result
    }
    func save(_ batch: CaptureAccumulator) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(batch.entries).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public enum CapturedLinkPolicy {
    /// Open only explicit web links, never commands, local files, credentials, or arbitrary schemes.
    public static func links(in text: String, maximum: Int = 3) -> [URL] {
        guard maximum > 0, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            let literal = String(text[range])
            guard literal.lowercased().hasPrefix("https://") || literal.lowercased().hasPrefix("http://"),
                  let url = match.url, let host = url.host, !host.isEmpty,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil,
                  seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }.prefix(maximum).map { $0 }
    }
}
