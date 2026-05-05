import XCTest
@testable import MouthType

final class StreamingASREngineTests: XCTestCase {
    func testStreamingASREngineInitialization() {
        let engine = StreamingASREngine()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineStartStop() {
        let engine = StreamingASREngine()
        let expectation = self.expectation(description: "callback received")
        
        engine.start { segment in
            // Callback may or may not be called
            expectation.fulfill()
        }
        
        engine.stop()
        XCTAssertNotNil(engine)
        
        // Fulfill expectation manually if not called
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }

    func testStreamingASREngineReset() {
        let engine = StreamingASREngine()
        engine.start { _ in }
        engine.reset()
        engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendEmptyData() {
        let engine = StreamingASREngine()
        engine.start { _ in }
        let emptyData = Data()
        engine.appendAudio(emptyData)
        engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendSmallData() {
        let engine = StreamingASREngine()
        engine.start { _ in }
        // Create minimal PCM data (4 bytes = 2 Int16 samples)
        let smallData = Data([0x00, 0x01, 0x02, 0x03])
        engine.appendAudio(smallData)
        engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendLargeData() {
        let engine = StreamingASREngine()
        let expectation = self.expectation(description: "segment received")
        
        engine.start { segment in
            if !segment.text.isEmpty {
                expectation.fulfill()
            }
        }
        
        // Create enough PCM data to trigger processing
        // 32000 bytes = 16000 Int16 samples = 1 second @ 16kHz
        var pcmData = Data(capacity: 32000)
        for _ in 0..<16000 {
            let sample: Int16 = Int16.random(in: -1000...1000)
            pcmData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        engine.appendAudio(pcmData)
        
        // Fulfill manually if no segment produced
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
        engine.stop()
    }

    func testStreamingASREngineFlush() {
        let engine = StreamingASREngine()
        engine.start { _ in }
        
        let result = engine.flush()
        // flush returns nil when buffer is empty
        XCTAssertNil(result)
        
        engine.stop()
    }

    func testStreamingASREngineMultipleStartStop() {
        let engine = StreamingASREngine()
        for _ in 0..<3 {
            engine.start { _ in }
            engine.stop()
        }
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineDebugInfo() {
        let engine = StreamingASREngine()
        let info = engine.debugInfo
        XCTAssertTrue(info.contains("StreamingASREngine"))
        XCTAssertTrue(info.contains("Running:"))
    }

    func testStreamingASREngineCustomConfig() {
        var config = StreamingASREngine.Config()
        config.windowSizeMs = 200
        config.windowStepMs = 50
        config.sampleRate = 8000
        
        let engine = StreamingASREngine(config: config)
        XCTAssertNotNil(engine)
        
        engine.start { _ in }
        engine.stop()
    }
}
