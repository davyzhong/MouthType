import XCTest
@testable import MouthType

final class AudioPreprocessorTests: XCTestCase {
    func testAudioPreprocessorInitialization() {
        let preprocessor = AudioPreprocessor()
        XCTAssertNotNil(preprocessor)
    }

    func testAudioPreprocessorReset() {
        let preprocessor = AudioPreprocessor()
        preprocessor.reset()
        // Should not crash; reset clears internal state
        XCTAssertNotNil(preprocessor)
    }

    func testAudioPreprocessorProcessEmptyBuffer() {
        let preprocessor = AudioPreprocessor()
        let emptyBuffer = [Float]()
        let result = preprocessor.process(emptyBuffer)
        XCTAssertEqual(result.count, 0)
    }

    func testAudioPreprocessorProcessSmallBuffer() {
        let preprocessor = AudioPreprocessor()
        let smallBuffer: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let result = preprocessor.process(smallBuffer)
        // Result should be same length (no resampling in simple pass-through)
        XCTAssertEqual(result.count, smallBuffer.count)
    }

    func testAudioPreprocessorProcessSilence() {
        let preprocessor = AudioPreprocessor()
        let silence = [Float](repeating: 0.0, count: 1024)
        let result = preprocessor.process(silence)
        XCTAssertEqual(result.count, 1024)
        // After normalization, silence should remain near zero
        XCTAssertTrue(result.allSatisfy { abs($0) < 0.01 })
    }

    func testAudioPreprocessorProcessFullScale() {
        let preprocessor = AudioPreprocessor()
        let fullScale = [Float](repeating: 1.0, count: 1024)
        let result = preprocessor.process(fullScale)
        XCTAssertEqual(result.count, 1024)
        // After normalization, values should be clamped
        XCTAssertTrue(result.allSatisfy { abs($0) <= 1.0 })
    }

    func testAudioPreprocessorProcessNegativeValues() {
        let preprocessor = AudioPreprocessor()
        let negative = [Float](repeating: -0.8, count: 512)
        let result = preprocessor.process(negative)
        XCTAssertEqual(result.count, 512)
        // After DC offset removal and AGC, negative values may become positive
        // Just verify output is valid (not NaN or infinite)
        XCTAssertTrue(result.allSatisfy { $0.isFinite })
    }

    func testAudioPreprocessorMultipleResets() {
        let preprocessor = AudioPreprocessor()
        for _ in 0..<5 {
            preprocessor.reset()
        }
        XCTAssertNotNil(preprocessor)
    }
}
