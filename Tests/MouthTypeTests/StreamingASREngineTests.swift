import XCTest
@testable import MouthType

final class StreamingASREngineTests: XCTestCase {
    func testStreamingASREngineInitialization() async {
        let engine = StreamingASREngine()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineStartStop() async {
        let engine = StreamingASREngine()

        await engine.start { segment in
            XCTFail("Start/stop without audio should not emit a segment: \(segment)")
        }

        await engine.stop()
        let info = await engine.debugInfo
        XCTAssertTrue(info.contains("Running: false"))
    }

    func testStreamingASREngineReset() async {
        let engine = StreamingASREngine()
        await engine.start { _ in }
        await engine.reset()
        await engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendEmptyData() async {
        let engine = StreamingASREngine()
        await engine.start { _ in }
        let emptyData = Data()
        await engine.appendAudio(emptyData)
        await engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendSmallData() async {
        let engine = StreamingASREngine()
        await engine.start { _ in }
        // Create minimal PCM data (4 bytes = 2 Int16 samples)
        let smallData = Data([0x00, 0x01, 0x02, 0x03])
        await engine.appendAudio(smallData)
        await engine.stop()
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineAppendLargeData() async {
        let engine = StreamingASREngine()
        let expectation = self.expectation(description: "segment received")
        expectation.assertForOverFulfill = false
        
        await engine.start { segment in
            if !segment.text.isEmpty {
                expectation.fulfill()
            }
        }
        
        // Create enough PCM data to trigger processing
        // 32000 bytes = 16000 Int16 samples = 1 second @ 16kHz
        var pcmData = Data(capacity: 32000)
        for _ in 0..<16000 {
            let sample: Int16 = 32767
            pcmData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        await engine.appendAudio(pcmData)

        await fulfillment(of: [expectation], timeout: 1.0)
        await engine.stop()
    }

    func testStreamingASREngineFlush() async {
        let engine = StreamingASREngine()
        await engine.start { _ in }
        
        let result = await engine.flush()
        // flush returns nil when buffer is empty
        XCTAssertNil(result)
        
        await engine.stop()
    }

    func testStreamingASREngineMultipleStartStop() async {
        let engine = StreamingASREngine()
        for _ in 0..<3 {
            await engine.start { _ in }
            await engine.stop()
        }
        XCTAssertNotNil(engine)
    }

    func testStreamingASREngineDebugInfo() async {
        let engine = StreamingASREngine()
        let info = await engine.debugInfo
        XCTAssertTrue(info.contains("StreamingASREngine"))
        XCTAssertTrue(info.contains("Running:"))
    }

    func testStreamingASREngineCustomConfig() async {
        var config = StreamingASREngine.Config()
        config.windowSizeMs = 200
        config.windowStepMs = 50
        config.sampleRate = 8000
        
        let engine = StreamingASREngine(config: config)
        XCTAssertNotNil(engine)
        
        await engine.start { _ in }
        await engine.stop()
    }
}
