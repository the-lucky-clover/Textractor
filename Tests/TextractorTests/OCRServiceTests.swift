//
 //  OCRServiceTests.swift
 //  TextractorTests
 //
 //  Unit tests for OCRService
 //

import XCTest
@testable import Textractor

final class OCRServiceTests: XCTestCase {
    
    // MARK: - Threshold Calculation
    
    func testThresholdAtZero() {
        let threshold = OCRService.threshold(for: 0.0)
        XCTAssertEqual(threshold, 0.02, accuracy: 0.001)
    }
    
    func testThresholdAtOne() {
        let threshold = OCRService.threshold(for: 1.0)
        XCTAssertEqual(threshold, 0.002, accuracy: 0.001)
    }
    
    func testThresholdAtHalf() {
        let threshold = OCRService.threshold(for: 0.5)
        // Linear interpolation: 0.002 + (1-0.5) * (0.02-0.002) = 0.002 + 0.5*0.018 = 0.011
        XCTAssertEqual(threshold, 0.011, accuracy: 0.001)
    }
    
    func testThresholdClampsBelowZero() {
        let threshold = OCRService.threshold(for: -0.5)
        XCTAssertEqual(threshold, 0.02, accuracy: 0.001)
    }
    
    func testThresholdClampsAboveOne() {
        let threshold = OCRService.threshold(for: 1.5)
        XCTAssertEqual(threshold, 0.002, accuracy: 0.001)
    }
    
    // MARK: - Auto Weirdness
    
    func testAutoWeirdnessEmptyObservations() {
        let result = OCRService.autoWeirdness(from: [])
        XCTAssertEqual(result, 0.5) // Default middle
    }
    
    func testAutoWeirdnessHighConfidence() {
        let observations = (0..<10).map { _ in
            TextObservation(
                text: "test",
                confidence: 0.95,
                boundingBox: .zero
            )
        }
        let result = OCRService.autoWeirdness(from: observations)
        // High confidence (0.95) + low variance → low weirdness
        XCTAssertLessThan(result, 0.3)
    }
    
    func testAutoWeirdnessLowConfidence() {
        let observations = (0..<10).map { _ in
            TextObservation(
                text: "test",
                confidence: 0.3,
                boundingBox: .zero
            )
        }
        let result = OCRService.autoWeirdness(from: observations)
        // Low confidence (0.3) → moderate weirdness (~0.49)
        XCTAssertGreaterThan(result, 0.4)
        XCTAssertLessThan(result, 0.6)
    }
    
    func testAutoWeirdnessHighVariance() {
        var observations: [TextObservation] = []
        for i in 0..<10 {
            let confidence = i % 2 == 0 ? 0.9 : 0.2
            observations.append(TextObservation(
                text: "test",
                confidence: Float(confidence),
                boundingBox: .zero
            ))
        }
        let result = OCRService.autoWeirdness(from: observations)
        // High variance → higher weirdness
        XCTAssertGreaterThan(result, 0.5)
    }
    
    // MARK: - Language Catalog
    
    func testAutomaticLanguagesNotEmpty() {
        let languages = OCRService.automaticLanguages()
        XCTAssertFalse(languages.isEmpty)
    }
    
    func testAutomaticLanguagesContainsEnglish() {
        let languages = OCRService.automaticLanguages()
        XCTAssertTrue(languages.contains("en-US"))
    }
    
    func testOcrLanguageCatalogNotEmpty() {
        let catalog = AppSettings.ocrLanguageCatalog
        XCTAssertFalse(catalog.isEmpty)
    }
    
    func testOcrLanguageCatalogHasValidEntries() {
        let catalog = AppSettings.ocrLanguageCatalog
        for entry in catalog {
            XCTAssertFalse(entry.code.isEmpty)
            XCTAssertFalse(entry.name.isEmpty)
            XCTAssertFalse(entry.flag.isEmpty)
        }
    }
}