import Foundation

/// Process execution result for subprocess operations
struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// Thread-safe data buffer for subprocess output
final class LockedData: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.withLock {
            data.append(newData)
        }
    }

    func getData() -> Data {
        lock.withLock { data }
    }
}
