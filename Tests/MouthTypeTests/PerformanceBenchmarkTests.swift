import XCTest
@testable import MouthType

/// Performance benchmarks for critical audio processing paths
final class PerformanceBenchmarkTests: XCTestCase {
    
    // MARK: - Audio Preprocessor Benchmarks
    
    func testAudioPreprocessorPerformanceSmallBuffer() {
        let preprocessor = AudioPreprocessor()
        let buffer = [Float](repeating: 0.5, count: 1600) // 100ms @ 16kHz
        
        measure {
            _ = preprocessor.process(buffer)
        }
    }
    
    func testAudioPreprocessorPerformanceLargeBuffer() {
        let preprocessor = AudioPreprocessor()
        let buffer = [Float](repeating: 0.5, count: 16000) // 1s @ 16kHz
        
        measure {
            _ = preprocessor.process(buffer)
        }
    }
    
    // MARK: - VAD Processor Benchmarks
    
    func testVADProcessorPerformance() {
        let vad = VADProcessor()
        
        measure {
            _ = vad.debugInfo
        }
    }
    
    // MARK: - Log Redaction Benchmarks
    
    func testLogRedactionPerformanceShortText() {
        let text = "User login: user@example.com with password secret123"
        
        measure {
            _ = LogRedaction.redactTranscript(text)
        }
    }
    
    func testLogRedactionPerformanceLongText() {
        let text = String(repeating: "User login: user@example.com with password secret123. ", count: 100)
        
        measure {
            _ = LogRedaction.redactTranscript(text)
        }
    }
    
    // MARK: - Chinese Converter Benchmarks
    
    func testChineseConverterPerformance() {
        let converter = ChineseConverter.shared
        let text = String(repeating: "這是繁體中文測試文本。", count: 10)
        
        measure {
            _ = converter.toSimplified(text)
        }
    }
    
    // MARK: - Transcript Stabilizer Benchmarks
    
    func testTranscriptStabilizerAppendPerformance() {
        let stabilizer = TranscriptStabilizer()
        let segment = ASRSegment(text: "test", isFinal: true, startTime: 0, endTime: 1)
        
        measure {
            stabilizer.append(segment)
        }
    }
    
    // MARK: - Audio Ring Buffer Benchmarks
    
    func testAudioRingBufferWritePerformance() {
        let buffer = AudioRingBuffer(durationMs: 500, sampleRate: 16000)
        let samples = [Float](repeating: 0.5, count: 1600)
        
        measure {
            buffer.write(samples)
            buffer.reset()
        }
    }
    
    // MARK: - ASR Result Processing Benchmarks
    
    func testASRResultSimplifiedTextPerformance() {
        let result = ASRResult(text: String(repeating: "這是測試", count: 20), language: "zh")
        
        measure {
            _ = result.simplifiedText
        }
    }
}
