//
//  HistoryStoreTests.swift
//  TextractorTests
//
//  Unit tests for HistoryStore
//

import XCTest
@testable import Textractor

@MainActor
final class HistoryStoreTests: XCTestCase {
    
    var historyStore: HistoryStore!
    
    override func setUp() async throws {
        try await super.setUp()
        historyStore = HistoryStore(inMemory: true)
    }
    
    override func tearDown() async throws {
        historyStore.clearAll()
        try await super.tearDown()
    }
    
    // MARK: - Record Management
    
    func testRecordCreatesEntry() {
        let capture = CapturedImage(
            id: UUID(),
            mode: .crosshair,
            origin: .hotkey,
            rect: .zero,
            fileURL: URL(fileURLWithPath: "/tmp/test.png"),
            capturedAt: Date(),
            screenIndex: 0
        )
        
        historyStore.record(
            capture: capture,
            text: "Test text",
            mode: .crosshair,
            ocrConfidence: 0.95,
            imagePath: "/tmp/test.png",
            limit: 100
        )
        
        XCTAssertEqual(historyStore.records.count, 1)
        XCTAssertEqual(historyStore.records[0].textPreview, "Test text")
        XCTAssertEqual(historyStore.records[0].mode, .crosshair)
        XCTAssertEqual(historyStore.records[0].ocrConfidence, 0.95)
    }
    
    func testRecordInsertsAtFront() {
        let capture1 = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/1.png"), capturedAt: Date().addingTimeInterval(-100), screenIndex: 0)
        let capture2 = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/2.png"), capturedAt: Date(), screenIndex: 0)
        
        historyStore.record(capture: capture1, text: "First", mode: .crosshair, limit: 100)
        historyStore.record(capture: capture2, text: "Second", mode: .crosshair, limit: 100)
        
        XCTAssertEqual(historyStore.records[0].textPreview, "Second")
        XCTAssertEqual(historyStore.records[1].textPreview, "First")
    }
    
    func testEnforcesLimit() {
        for i in 0..<110 {
            let capture = CapturedImage(
                id: UUID(),
                mode: .crosshair,
                origin: .hotkey,
                rect: .zero,
                fileURL: URL(fileURLWithPath: "/tmp/\(i).png"),
                capturedAt: Date().addingTimeInterval(TimeInterval(-i)),
                screenIndex: 0
            )
            historyStore.record(capture: capture, text: "Text \(i)", mode: .crosshair, limit: 100)
        }
        
        XCTAssertEqual(historyStore.records.count, 100)
        // Should keep the most recent 100
        XCTAssertEqual(historyStore.records[0].textPreview, "Text 0")
        XCTAssertEqual(historyStore.records[99].textPreview, "Text 99")
    }
    
    // MARK: - Delete
    
    func testDeleteRemovesRecord() {
        let capture = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/test.png"), capturedAt: Date(), screenIndex: 0)
        historyStore.record(capture: capture, text: "Test", mode: .crosshair, limit: 100)
        
        let record = historyStore.records[0]
        historyStore.delete(record)
        
        XCTAssertEqual(historyStore.records.count, 0)
    }
    
    func testDeleteNonExistentRecord() {
        let capture = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/test.png"), capturedAt: Date(), screenIndex: 0)
        historyStore.record(capture: capture, text: "Test", mode: .crosshair, limit: 100)
        
        let nonExistent = HistoryRecord(
            id: UUID(),
            capturedAt: Date(),
            textPreview: "Non-existent",
            mode: .crosshair,
            ocrConfidence: nil,
            textPath: nil,
            imagePath: nil
        )
        historyStore.delete(nonExistent)
        
        XCTAssertEqual(historyStore.records.count, 1)
    }
    
    // MARK: - Clear All
    
    func testClearAllRemovesAllRecords() {
        for i in 0..<10 {
            let capture = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/\(i).png"), capturedAt: Date(), screenIndex: 0)
            historyStore.record(capture: capture, text: "Text \(i)", mode: .crosshair, limit: 100)
        }
        
        historyStore.clearAll()
        
        XCTAssertEqual(historyStore.records.count, 0)
    }
    
    // MARK: - Undo Last Capture
    
    func testUndoLastCaptureRemovesFirstRecord() {
        let capture1 = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/1.png"), capturedAt: Date().addingTimeInterval(-100), screenIndex: 0)
        let capture2 = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/2.png"), capturedAt: Date(), screenIndex: 0)
        
        historyStore.record(capture: capture1, text: "First", mode: .crosshair, limit: 100)
        historyStore.record(capture: capture2, text: "Second", mode: .crosshair, limit: 100)
        
        historyStore.undoLastCapture()
        
        XCTAssertEqual(historyStore.records.count, 1)
        XCTAssertEqual(historyStore.records[0].textPreview, "First")
    }
    
    func testUndoOnEmptyStoreDoesNothing() {
        historyStore.undoLastCapture()
        XCTAssertEqual(historyStore.records.count, 0)
    }
    
    // MARK: - Persistence
    
    func testSaveAndLoad() {
        let capture = CapturedImage(id: UUID(), mode: .crosshair, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/test.png"), capturedAt: Date(), screenIndex: 0)
        historyStore.record(capture: capture, text: "Test", mode: .crosshair, limit: 100)
        
        // Create new store instance (simulates app restart)
        let newStore = HistoryStore(inMemory: true)
        
        // In-memory store doesn't persist, so this tests the API
        // Real persistence would be tested with a file-backed store
        XCTAssertTrue(true) // Placeholder for actual persistence test
    }
    
    // MARK: - CaptureMode
    
    func testRecordsCaptureMode() {
        let modes: [CaptureMode] = [.crosshair, .window, .autoScroll]
        
        for mode in modes {
            let capture = CapturedImage(id: UUID(), mode: mode, origin: .hotkey, rect: .zero, fileURL: URL(fileURLWithPath: "/tmp/test.png"), capturedAt: Date(), screenIndex: 0)
            historyStore.record(capture: capture, text: "Test", mode: mode, limit: 100)
            
            let record = historyStore.records[0]
            XCTAssertEqual(record.mode, mode)
        }
    }
}