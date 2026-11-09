import UIKit
import CoreText
import CoreImage

enum PacketLayout: String, CaseIterable, Identifiable {
    case transcript = "Transcript", conversation = "Message layout"
    var id: String { rawValue }
}
struct PacketOptions {
    var includeTimestamps = true
    var includeSourcePages = true
    var includeAuditJSON = true
    var includeOriginalFiles = true
    var layout: PacketLayout = .transcript
}
struct PacketTextBlock {
    var lines: [String]
    var side: MessageSide
    var heading: Bool
    var height: CGFloat { CGFloat(lines.count) * 15 + 16 }
}
enum PacketPage {
    case text([PacketTextBlock])
    case source(SourceScreenshot)
}

@MainActor
enum PrintPacketRenderer {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter
    static let contentHeight: CGFloat = 650
    static let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// CoreText chooses UTF-16 boundaries, including long tokens and emoji, without truncation.
    static func wrap(_ text: String, width: CGFloat) -> [String] {
        guard !text.isEmpty else { return [""] }
        let value = NSAttributedString(string: text, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(value)
        let string = text as NSString
        var offset = 0
        var lines: [String] = []
        while offset < string.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, offset, Double(width)))
            let range = NSRange(location: offset, length: min(count, string.length - offset))
            lines.append(string.substring(with: range))
            offset += range.length
        }
        return lines
    }

    static func pages(archive: ConversationArchive, options: PacketOptions) throws -> [PacketPage] {
        var pages: [PacketPage] = []
        var current: [PacketTextBlock] = []
        var used: CGFloat = 0
        func add(_ text: String, side: MessageSide = .unassigned, heading: Bool = false) throws {
            let width: CGFloat = options.layout == .conversation && !heading ? 410 : 516
            var remaining = wrap(text, width: width)
            while !remaining.isEmpty {
                let capacity = Int((contentHeight - used - 16) / 15)
                if capacity < 1 {
                    pages.append(.text(current)); current = []; used = 0
                    guard pages.count < 500 else { throw ConversationError.tooManyPages }
                    continue
                }
                let count = min(capacity, remaining.count)
                let block = PacketTextBlock(lines: Array(remaining.prefix(count)), side: side, heading: heading)
                current.append(block); used += block.height
                remaining.removeFirst(count)
            }
        }
        let omitted = archive.blocks.filter { $0.excluded || $0.kind == .interface || (!options.includeTimestamps && $0.kind == .timestamp) }.count
        try add("\(archive.title)\nOCR-derived working transcript. Review against original screenshots.\n\(archive.sources.count) sources; \(archive.blocks.count) OCR blocks; \(omitted) blocks omitted from this presentation.\nSpeaker names, message directions, and manually entered timestamps are user supplied. Screenshot timestamps are reproduced only where visible. Import dates are not message dates.", heading: true)
        let sourceNumbers = Dictionary(uniqueKeysWithValues: archive.sources.enumerated().map { ($0.element.id, $0.offset + 1) })
        for (index, block) in archive.blocks.enumerated() {
            guard !block.excluded, block.kind != .interface,
                  options.includeTimestamps || block.kind != .timestamp else { continue }
            let speaker = block.speaker.isEmpty ? "Unassigned speaker" : "Speaker (user supplied): \(block.speaker)"
            var label = "S\(sourceNumbers[block.sourceID, default: 0]) / block \(index + 1) · \(speaker)"
            if block.kind == .timestamp { label = "S\(sourceNumbers[block.sourceID, default: 0]) / block \(index + 1) · Visible timestamp (OCR)" }
            if block.isEdited { label += " · EDITED" }
            if options.includeTimestamps, !block.userTimestamp.isEmpty { label += "\nUser-entered timestamp: \(block.userTimestamp)" }
            try add(label + "\n" + block.text, side: block.side)
        }
        try add("Source manifest\nSHA-256 identifies the bytes imported by this app; it does not establish when a screenshot was made. Source images remain separate from the reconstructed text.", heading: true)
        for (index, source) in archive.sources.enumerated() {
            try add("S\(index + 1): \(source.filename)\nImported: \(source.importedAt.ISO8601Format())\nSHA-256: \(source.sha256)", heading: true)
        }
        let excluded = archive.blocks.filter(\.excluded)
        if !excluded.isEmpty {
            try add("Reviewed exclusions\n" + excluded.map { "\($0.id.uuidString): \($0.exclusionReason)" }.joined(separator: "\n"), heading: true)
        }
        if !current.isEmpty { pages.append(.text(current)) }
        if options.includeSourcePages { pages += archive.sources.map { .source($0) } }
        guard pages.count <= 500 else { throw ConversationError.tooManyPages }
        return pages
    }

    static func export(store: ConversationStore, options: PacketOptions) throws -> [URL] {
        let archive = store.archive
        // Verify all originals before creating any user-shareable output.
        for source in archive.sources { _ = try store.originalData(source) }
        let planned = try pages(archive: archive, options: options)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Packet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = directory.appendingPathComponent("Conversation-Packet.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        do {
            var imageError: Error?
            try renderer.writePDF(to: pdf) { context in
                for (index, page) in planned.enumerated() {
                    context.beginPage()
                    UIColor.white.setFill(); context.cgContext.fill(CGRect(origin: .zero, size: pageSize))
                    draw(archive.title, rect: CGRect(x: 36, y: 20, width: 540, height: 20), font: .boldSystemFont(ofSize: 12))
                    draw(options.layout == .conversation ? "Reconstructed message layout · OCR-derived" : "Derived transcript · OCR and user edits",
                         rect: CGRect(x: 36, y: 40, width: 540, height: 15), font: .systemFont(ofSize: 9))
                    switch page {
                    case .text(let blocks):
                        var y: CGFloat = 68
                        for block in blocks {
                            let bubble = options.layout == .conversation && !block.heading
                            let width: CGFloat = bubble ? 434 : 540
                            let x: CGFloat = bubble && block.side == .outgoing ? 576 - width : 36
                            if bubble {
                                let path = UIBezierPath(roundedRect: CGRect(x: x, y: y + 2, width: width, height: block.height - 4), cornerRadius: 10)
                                UIColor.black.setStroke(); path.lineWidth = 0.6; path.stroke()
                            }
                            for (lineIndex, line) in block.lines.enumerated() {
                                draw(line.trimmingCharacters(in: .newlines),
                                     rect: CGRect(x: x + 12, y: y + 8 + CGFloat(lineIndex) * 15, width: width - 24, height: 15), font: font)
                            }
                            y += block.height
                        }
                    case .source(let source):
                        do {
                            let data = try store.originalData(source)
                            guard let original = ConversationStore.thumbnail(data: data, maximum: 2400) else { throw ConversationError.invalidImage }
                            let ci = CIImage(cgImage: original).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                            guard let gray = CIContext().createCGImage(ci, from: ci.extent) else { throw ConversationError.invalidImage }
                            draw("Source image: \(source.filename) · grayscale rendering", rect: CGRect(x: 36, y: 65, width: 540, height: 30), font: .systemFont(ofSize: 10))
                            let image = UIImage(cgImage: gray)
                            let scale = min(540 / image.size.width, 620 / image.size.height)
                            image.draw(in: CGRect(x: (612 - image.size.width * scale) / 2, y: 100,
                                                  width: image.size.width * scale, height: image.size.height * scale))
                        } catch { imageError = error }
                    }
                    draw("Page \(index + 1) of \(planned.count) · Textractor Pro · \(options.includeTimestamps ? "Transcript timestamps included" : "Transcript timestamps hidden")",
                         rect: CGRect(x: 36, y: 752, width: 540, height: 20), font: .systemFont(ofSize: 9))
                }
            }
            if let imageError { throw imageError }
            var urls = [pdf]
            if options.includeAuditJSON {
                let json = directory.appendingPathComponent("Full-Source-Text-and-Edit-History.json")
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(archive).write(to: json, options: [.atomic, .completeFileProtection])
                urls.append(json)
            }
            if options.includeOriginalFiles {
                for (index, source) in archive.sources.enumerated() {
                    let suffix = (source.relativePath as NSString).pathExtension
                    let original = directory.appendingPathComponent(String(format: "Source-%02d", index + 1) + "." + suffix)
                    try store.originalData(source).write(to: original, options: [.atomic, .completeFileProtection])
                    urls.append(original)
                }
            }
            return urls
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func draw(_ text: String, rect: CGRect, font: UIFont) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: UIColor.black])
    }
}
