import AVFoundation
import Foundation
import os

private let ringBufferLog = Logger(subsystem: "com.mouthtype", category: "RingBuffer")

/// Circular buffer for audio pre-roll during VAD activation
///
/// Stores PCM audio samples while VAD is in activating state.
/// When VAD transitions to active, the buffered audio is emitted first,
/// ensuring no speech is clipped at the beginning.
final class AudioRingBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private var capacity: Int
    private var writeIndex: Int = 0
    private var isFull: Bool = false

    /// Initialize with capacity for specified duration
    /// - Parameters:
    ///   - durationMs: Duration in milliseconds to buffer
    ///   - sampleRate: Audio sample rate (default 16kHz for ASR)
    init(durationMs: Int = 500, sampleRate: Double = 16000) {
        // Calculate samples needed (mono audio)
        self.capacity = Int(Double(durationMs) / 1000.0 * sampleRate)
        self.buffer = []
        self.buffer.reserveCapacity(self.capacity)
        ringBufferLog.debug("Ring buffer initialized: \(self.capacity) samples (\(durationMs)ms @ \(sampleRate)Hz)")
    }

    /// Write audio samples to buffer
    /// - Parameter samples: Array of PCM float samples (-1.0 to 1.0)
    func write(_ samples: [Float]) {
        for sample in samples {
            if isFull {
                // Overwrite oldest sample
                buffer[writeIndex] = sample
            } else {
                buffer.append(sample)
                if buffer.count == capacity {
                    isFull = true
                }
            }
            writeIndex = (writeIndex + 1) % capacity
        }
    }

    /// Read all buffered data and reset
    /// - Returns: Array of buffered samples in chronological order
    func readAndReset() -> [Float] {
        defer { reset() }

        if !isFull {
            // Buffer not full - return all samples in order
            return buffer
        } else {
            // Buffer full - reorder from writeIndex
            var result: [Float] = []
            result.reserveCapacity(capacity)

            // From writeIndex to end
            for i in writeIndex..<buffer.count {
                result.append(buffer[i])
            }
            // From start to writeIndex
            for i in 0..<writeIndex {
                result.append(buffer[i])
            }

            return result
        }
    }

    /// Reset buffer without reading
    func reset() {
        buffer.removeAll()
        buffer.reserveCapacity(capacity)
        writeIndex = 0
        isFull = false
        ringBufferLog.debug("Ring buffer reset")
    }

    /// Current buffer duration in milliseconds
    var durationMs: Double {
        Double(buffer.count) / 16000.0 * 1000.0
    }

    /// Whether buffer has enough data for pre-roll
    var hasPreRoll: Bool {
        buffer.count >= capacity / 2 // At least 50% full
    }

    /// Current number of samples buffered
    var count: Int {
        buffer.count
    }

    /// Convert float samples to Int16 PCM data for ASR
    func readAndResetAsPCM() -> Data {
        let samples = readAndReset()
        var pcmData = Data(capacity: samples.count * 2)

        for sample in samples {
            let int16 = Int16(max(-1.0, min(1.0, sample)) * 32767.0)
            pcmData.append(contentsOf: withUnsafeBytes(of: int16.bigEndian) { Array($0) })
        }

        return pcmData
    }
}
