import Foundation
import SwiftUI
import UIKit
import Vision
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ConversationError: LocalizedError {
    case invalidImage, tooLarge, sourceLimit, missingOriginal, corruptArchive, tooManyPages
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This file could not be read as an image."
        case .tooLarge: return "Import images under 30 megapixels and 50 MB."
        case .sourceLimit: return "This packet supports up to 50 screenshots. Export it before starting another packet."
        case .missingOriginal: return "An original screenshot is missing or its checksum has changed. Export stopped."
        case .corruptArchive: return "The saved packet could not be opened. Its files have been retained; new imports are blocked."
        case .tooManyPages: return "This packet exceeds the 500-page export limit. No partial PDF was produced."
        }
    }
}

@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var archive = ConversationArchive()
    @Published var error: String?
    @Published private(set) var importStatus = ""
    private(set) var loadFailed = false
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ConversationPacket", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let url = self.directory.appendingPathComponent("archive.json")
            if FileManager.default.fileExists(atPath: url.path) {
                archive = try JSONDecoder().decode(ConversationArchive.self, from: Data(contentsOf: url))
            }
        } catch { loadFailed = true; self.error = ConversationError.corruptArchive.localizedDescription }
    }

    func commit(_ candidate: ConversationArchive) throws {
        guard !loadFailed else { throw ConversationError.corruptArchive }
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: directory.appendingPathComponent("archive.json"), options: [.atomic, .completeFileProtection])
        archive = candidate
    }

    @discardableResult
    func update(_ block: TranscriptBlock) -> Bool {
        do { var candidate = archive; candidate.replace(block); try commit(candidate); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func rename(_ title: String) {
        do {
            var candidate = archive
            candidate.changes.append(.init(action: "packet title", before: candidate.title, after: title))
            candidate.title = String(title.prefix(150))
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func moveSources(from: IndexSet, to: Int) {
        do {
            var candidate = archive
            let old = candidate.sources.map { $0.id.uuidString }.joined(separator: ",")
            candidate.sources.move(fromOffsets: from, toOffset: to)
            candidate.changes.append(.init(action: "source order", before: old,
                                          after: candidate.sources.map { $0.id.uuidString }.joined(separator: ",")))
            let order = Dictionary(uniqueKeysWithValues: candidate.sources.enumerated().map { ($0.element.id, $0.offset) })
            candidate.blocks.sort { order[$0.sourceID, default: 0] < order[$1.sourceID, default: 0] }
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func excludeOverlap(_ proposal: OverlapProposal) {
        do {
            var candidate = archive
            for id in proposal.laterIDs {
                guard var block = candidate.blocks.first(where: { $0.id == id }) else { continue }
                block.excluded = true
                block.exclusionReason = "User confirmed screenshot overlap; earlier blocks: " + proposal.earlierIDs.map(\.uuidString).joined(separator: ", ")
                candidate.replace(block)
            }
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func keepOverlap(_ proposal: OverlapProposal) {
        do {
            var candidate = archive
            candidate.reviewedOverlaps.append(proposal.id)
            candidate.changes.append(.init(action: "keep both overlap regions", before: "pending", after: proposal.id))
            try commit(candidate)
        } catch { self.error = error.localizedDescription }
    }

    func importImage(_ data: Data, name: String) async throws {
        guard !loadFailed else { throw ConversationError.corruptArchive }
        guard archive.sources.count < 50 else { throw ConversationError.sourceLimit }
        guard data.count <= 50_000_000 else { throw ConversationError.tooLarge }
        try Task.checkCancellation()
        let id = UUID()
        importStatus = "Recognizing \(name)…"
        defer { importStatus = "" }
        let blocks = try await Task.detached(priority: .userInitiated) {
            try Self.recognize(data: data, sourceID: id)
        }.value
        try Task.checkCancellation()
        let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        let type = imageSource.flatMap { CGImageSourceGetType($0) }.map { $0 as String }
        let suffix = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "image"
        let relativePath = "\(id.uuidString).\(suffix)"
        let url = directory.appendingPathComponent(relativePath)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        do {
            var candidate = archive
            candidate.sources.append(.init(id: id, filename: name, relativePath: relativePath,
                                           sha256: Self.digest(data), importedAt: Date()))
            candidate.blocks.append(contentsOf: blocks)
            candidate.changes.append(.init(action: "import", before: "", after: "\(id.uuidString): \(blocks.count) OCR blocks"))
            try commit(candidate)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    nonisolated static func recognize(data: Data, sourceID: UUID) throws -> [TranscriptBlock] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ConversationError.invalidImage }
        guard width > 0, height > 0, Double(width) * Double(height) <= 30_000_000 else { throw ConversationError.tooLarge }
        guard let image = thumbnail(data: data, maximum: 4096) else { throw ConversationError.invalidImage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.002
        try VNImageRequestHandler(cgImage: image).perform([request])
        let results = (request.results ?? []).sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        return results.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            return TranscriptBlock(sourceID: sourceID, originalText: text.string, rect: observation.boundingBox,
                                   confidence: text.confidence, kind: ConversationLogic.isTimestamp(text.string) ? .timestamp : .message)
        }
    }

    nonisolated static func thumbnail(data: Data, maximum: Int = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximum
        ] as CFDictionary)
    }

    func originalData(_ source: SourceScreenshot) throws -> Data {
        let data = try Data(contentsOf: directory.appendingPathComponent(source.relativePath))
        guard Self.digest(data) == source.sha256 else { throw ConversationError.missingOriginal }
        return data
    }

    func startNewPacket() {
        do {
            // Archive previous packet intact; the visible workspace starts empty.
            let parent = directory.deletingLastPathComponent().appendingPathComponent("SavedPackets", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if !archive.sources.isEmpty {
                try FileManager.default.copyItem(at: directory, to: parent.appendingPathComponent(UUID().uuidString))
            }
            try commit(ConversationArchive())
        } catch { self.error = error.localizedDescription }
    }
}
