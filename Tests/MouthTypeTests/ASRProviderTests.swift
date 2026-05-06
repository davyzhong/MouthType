import XCTest
@testable import MouthType

final class ASRProviderTests: XCTestCase {
    func testASRProviderProtocolExists() {
        let type: Any.Type = ASRProvider.self
        XCTAssertNotNil(type)
    }

    func testASRResultInitialization() {
        let result = ASRResult(text: "test transcription", language: "zh")
        XCTAssertEqual(result.text, "test transcription")
        XCTAssertEqual(result.language, "zh")
    }

    func testASRResultEmptyText() {
        let result = ASRResult(text: "", language: nil)
        XCTAssertEqual(result.text, "")
        XCTAssertNil(result.language)
    }

    func testASRResultSimplifiedText() {
        let result = ASRResult(text: "hello", language: "en")
        XCTAssertFalse(result.simplifiedText.isEmpty)
    }

    func testASRSegmentInitialization() {
        let segment = ASRSegment(text: "segment text", isFinal: false, startTime: 0.0, endTime: 1.0)
        XCTAssertEqual(segment.text, "segment text")
        XCTAssertFalse(segment.isFinal)
        XCTAssertEqual(segment.startTime, 0.0)
        XCTAssertEqual(segment.endTime, 1.0)
    }

    func testASRSegmentFinal() {
        let segment = ASRSegment(text: "final", isFinal: true, startTime: 0.0, endTime: 2.0)
        XCTAssertTrue(segment.isFinal)
    }

    func testASRProviderTypeDisplayNames() {
        let types: [ASRProviderType] = [.localWhisper, .localParaformer, .bailianStreaming, .bailian]
        for type in types {
            XCTAssertFalse(type.displayName.isEmpty)
        }
    }

    func testASRProviderTypeRawValues() {
        XCTAssertEqual(ASRProviderType.localWhisper.rawValue, "Local Whisper (whisper.cpp)")
        XCTAssertEqual(ASRProviderType.localParaformer.rawValue, "Local Paraformer (中文最佳)")
    }
}
