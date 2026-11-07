import XCTest
import UIKit
import PDFKit
@testable import TextractorMobile

@MainActor
final class ConversationTests: XCTestCase {
    private func block(_ text: String, source: UUID = UUID()) -> TranscriptBlock {
        TranscriptBlock(sourceID: source, originalText: text, rect: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.1), confidence: 0.95)
    }
    private func source(_ id: UUID) -> SourceScreenshot {
        .init(id: id, filename: "Synthetic.png", relativePath: "\(id).png", sha256: "fixture", importedAt: Date(timeIntervalSince1970: 0))
    }

    func testTimestampClassificationDoesNotInventDates() {
        for value in ["Today 9:41 AM", "Yesterday", "11:42 PM", "Nov 7, 2026"] { XCTAssertTrue(ConversationLogic.isTimestamp(value), value) }
        for value in ["I will arrive at 9:41 AM", "We met yesterday", "Pay 1200 today"] { XCTAssertFalse(ConversationLogic.isTimestamp(value), value) }
    }
    func testRepeatedShortMessagesAreNotAutomaticallyDuplicates() {
        let a = UUID(), b = UUID()
        var archive = ConversationArchive(); archive.sources = [source(a), source(b)]
        archive.blocks = [block("Yes", source: a), block("Yes", source: a), block("Yes", source: b), block("Yes", source: b)]
        XCTAssertTrue(ConversationLogic.overlaps(in: archive).isEmpty)
        XCTAssertEqual(archive.blocks.count, 4)
    }
    func testOverlapIsProposalOnlyAndChangedAmountsDoNotMatch() {
        let a = UUID(), b = UUID()
        var archive = ConversationArchive(); archive.sources = [source(a), source(b)]
        let texts = ["Please bring the blue folder.", "I will meet you at the library."]
        archive.blocks = texts.map { block($0, source: a) } + texts.map { block($0, source: b) }
        XCTAssertEqual(ConversationLogic.overlaps(in: archive).count, 1)
        XCTAssertFalse(archive.blocks.contains(where: \.excluded))
        XCTAssertEqual(ConversationLogic.similarity("Payment is 100 dollars", "Payment is 900 dollars"), 0)
    }
    func testEditsPreserveOriginalAndLogBeforeAfter() {
        var archive = ConversationArchive(); let original = block("Original wording")
        archive.blocks = [original]
        var edited = original; edited.editedText = "Corrected wording"; edited.excluded = true; edited.exclusionReason = "Duplicate source region"
        archive.replace(edited)
        XCTAssertEqual(archive.blocks[0].originalText, "Original wording")
        XCTAssertEqual(archive.blocks[0].text, "Corrected wording")
        XCTAssertEqual(archive.changes.count, 1)
        XCTAssertTrue(archive.changes[0].before.contains("Original wording"))
        XCTAssertTrue(archive.changes[0].after.contains("Corrected wording"))
    }
    func testFuzzySearchAndVectorRanking() {
        XCTAssertGreaterThan(ConversationLogic.fuzzyScore(query: "libary", text: "Please meet me at the library"), 0.7)
        XCTAssertEqual(ConversationLogic.fuzzyScore(query: "900", text: "Payment is 100"), 0)
        XCTAssertEqual(ConversationSearch.cosine([1, 0], [1, 0]), 1, accuracy: 0.00001)
        XCTAssertEqual(ConversationSearch.cosine([1, 0], [0, 1]), 0)
        XCTAssertEqual(ConversationSearch.cosine([], []), 0)
    }
    func testExactSearchPreservesSourceReferences() async {
        let engine = ConversationSearch()
        let original = block("Bring the blue folder")
        let found = await engine.search("BLUE FOLDER", mode: .exact, blocks: [original, block("Unrelated message")])
        XCTAssertEqual(found.hits.map(\.id), [original.id])
        XCTAssertEqual(found.hits.first?.block.sourceID, original.sourceID)
    }
    func testCoreTextWrappingPreservesEveryCharacter() {
        let text = String(repeating: "Emoji 👨‍👩‍👧‍👦 café 漢字 with a verylongunbrokentoken.\n", count: 30)
        XCTAssertEqual(PrintPacketRenderer.wrap(text, width: 150).joined(), text)
    }
    func testOptionalTimestampChangesOnlyPresentation() throws {
        let id = UUID(); var archive = ConversationArchive(); archive.sources = [source(id)]
        var stamp = block("Today 9:41 AM", source: id); stamp.kind = .timestamp
        archive.blocks = [stamp, block("Keep this message", source: id)]
        var options = PacketOptions(); options.includeTimestamps = false; options.includeSourcePages = false
        let pages = try PrintPacketRenderer.pages(archive: archive, options: options)
        let text = pages.compactMap { if case .text(let blocks) = $0 { return blocks.flatMap(\.lines).joined() }; return nil }.joined()
        XCTAssertFalse(text.contains("Today 9:41 AM"))
        XCTAssertTrue(text.contains("Keep this message"))
        XCTAssertEqual(archive.blocks.count, 2)
        XCTAssertEqual(archive.blocks[0].originalText, "Today 9:41 AM")
    }
    func testImportPersistenceChecksumAndNumberedPDF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConversationStore(directory: directory)
        let data = MobileFixture.image()
        let start = ProcessInfo.processInfo.systemUptime
        try await store.importImage(data, name: "Synthetic conversation.png")
        print("MOBILE_IMPORT_MS=\((ProcessInfo.processInfo.systemUptime - start) * 1000)")
        XCTAssertEqual(store.archive.sources.count, 1)
        XCTAssertTrue(store.archive.blocks.map(\.text).joined(separator: " ").contains("blue folder"))
        XCTAssertEqual(try store.originalData(store.archive.sources[0]), data)
        XCTAssertEqual(ConversationStore(directory: directory).archive.blocks.count, store.archive.blocks.count)
        let files = try PrintPacketRenderer.export(store: store, options: PacketOptions())
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let transcriptAttachment = XCTAttachment(contentsOfFile: files[0])
        transcriptAttachment.name = "Synthetic transcript packet"
        transcriptAttachment.lifetime = .keepAlways
        add(transcriptAttachment)
        let pdf = try XCTUnwrap(PDFDocument(url: files[0]))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 2)
        for index in 0..<pdf.pageCount {
            XCTAssertTrue(pdf.page(at: index)?.string?.contains("Page \(index + 1) of \(pdf.pageCount)") == true)
            XCTAssertEqual(pdf.page(at: index)?.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        }
        XCTAssertTrue(pdf.string?.contains("blue folder") == true)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(try Data(contentsOf: files[2]), data)
        var messageOptions = PacketOptions(); messageOptions.layout = .conversation
        let messageFiles = try PrintPacketRenderer.export(store: store, options: messageOptions)
        defer { try? FileManager.default.removeItem(at: messageFiles[0].deletingLastPathComponent()) }
        let messageAttachment = XCTAttachment(contentsOfFile: messageFiles[0])
        messageAttachment.name = "Synthetic reconstructed message packet"
        messageAttachment.lifetime = .keepAlways
        add(messageAttachment)
        try Data("altered".utf8).write(to: directory.appendingPathComponent(store.archive.sources[0].relativePath))
        XCTAssertThrowsError(try PrintPacketRenderer.export(store: store, options: PacketOptions()))
    }
    func testLongMessagePaginationHasNoTruncation() throws {
        var archive = ConversationArchive()
        archive.blocks = [block(String(repeating: "A long message that must continue on the next page. ", count: 300) + "END_SENTINEL")]
        var options = PacketOptions(); options.layout = .conversation; options.includeSourcePages = false
        let pages = try PrintPacketRenderer.pages(archive: archive, options: options)
        XCTAssertGreaterThan(pages.count, 2)
        let text = pages.compactMap { if case .text(let blocks) = $0 { return blocks.flatMap(\.lines).joined() }; return nil }.joined()
        XCTAssertTrue(text.contains("END_SENTINEL"))
        XCTAssertTrue(text.contains(archive.blocks[0].text))
    }
}
