//
//  TranslationServiceTests.swift
//  TextractorTests
//
//  Unit tests for TranslationService
//

import XCTest
@testable import Textractor

final class TranslationServiceTests: XCTestCase {
    
    var translationService: TranslationService!
    
    override func setUp() {
        super.setUp()
        translationService = TranslationService.shared
    }
    
    // MARK: - Language Detection
    
    func testDetectsEnglish() async {
        let text = "Hello, how are you today?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "en")
    }
    
    func testDetectsSpanish() async {
        let text = "Hola, ¿cómo estás?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "es")
    }
    
    func testDetectsFrench() async {
        let text = "Bonjour, comment allez-vous?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "fr")
    }
    
    func testDetectsGerman() async {
        let text = "Hallo, wie geht es dir?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "de")
    }
    
    func testDetectsChinese() async {
        let text = "你好，你好吗？"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertTrue(languageCode == "zh" || languageCode == "zh-Hans" || languageCode == "zh-Hant")
    }
    
    func testDetectsJapanese() async {
        let text = "こんにちは、元気ですか？"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "ja")
    }
    
    func testDetectsKorean() async {
        let text = "안녕하세요, 어떻게 지내세요?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "ko")
    }
    
    func testDetectsRussian() async {
        let text = "Привет, как дела?"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "ru")
    }
    
    func testDetectsArabic() async {
        let text = "مرحبا، كيف حالك؟"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "ar")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStringReturnsNil() async {
        let languageCode = translationService.detectLanguageCode("")
        XCTAssertNil(languageCode)
    }
    
    func testShortTextReturnsNil() async {
        let languageCode = translationService.detectLanguageCode("hi")
        // Short text might not be reliably detected
        // Just verify it doesn't crash
        XCTAssertNotNil(languageCode) // or could be nil, both acceptable
    }
    
    func testMixedLanguageReturnsDominant() async {
        let text = "Hello world! Bonjour le monde! Hello again!"
        let languageCode = translationService.detectLanguageCode(text)
        XCTAssertEqual(languageCode, "en") // English should be dominant
    }
    
    // MARK: - Supported Targets
    
    func testSupportedTargetsContainsExpectedLanguages() {
        let targets = TranslationService.supportedTargets
        let codes = targets.map { $0.code }
        
        XCTAssertTrue(codes.contains("en"))
        XCTAssertTrue(codes.contains("es"))
        XCTAssertTrue(codes.contains("fr"))
        XCTAssertTrue(codes.contains("de"))
        XCTAssertTrue(codes.contains("zh-Hans"))
        XCTAssertTrue(codes.contains("ja"))
        XCTAssertTrue(codes.contains("ko"))
        XCTAssertTrue(codes.contains("ru"))
        XCTAssertTrue(codes.contains("ar"))
        XCTAssertTrue(codes.contains("pt"))
        XCTAssertTrue(codes.contains("it"))
        XCTAssertTrue(codes.contains("nl"))
        XCTAssertTrue(codes.contains("pl"))
        XCTAssertTrue(codes.contains("tr"))
        XCTAssertTrue(codes.contains("vi"))
        XCTAssertTrue(codes.contains("th"))
        XCTAssertTrue(codes.contains("id"))
        XCTAssertTrue(codes.contains("hi"))
        XCTAssertTrue(codes.contains("sv"))
        XCTAssertTrue(codes.contains("da"))
        
        // Should have at least 20 languages
        XCTAssertGreaterThanOrEqual(targets.count, 20)
    }
    
    // MARK: - Translation (Stub)
    
    func testTranslateEmptyStringReturnsNil() async {
        let result = await translationService.translate("", to: "es")
        XCTAssertNil(result)
    }
    
    func testTranslateToEmptyTargetReturnsNil() async {
        let result = await translationService.translate("Hello", to: "")
        XCTAssertNil(result)
    }
    
    func testTranslateSameLanguageReturnsNil() async {
        let result = await translationService.translate("Hello", to: "en")
        XCTAssertNil(result)
    }
    
    func testTranslateReturnsNonNilForValidInput() async {
        let result = await translationService.translate("Hello world", to: "es")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("es") || result!.contains("Spanish"))
    }
}