import XCTest
@testable import MouthType

final class ProcessResultTests: XCTestCase {
    func testProcessResultInitialization() {
        let result = ProcessResult(stdout: "output", stderr: "", exitCode: 0)
        XCTAssertEqual(result.stdout, "output")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testProcessResultEmptyOutput() {
        let result = ProcessResult(stdout: "", stderr: "", exitCode: 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testProcessResultErrorExitCode() {
        let result = ProcessResult(stdout: "", stderr: "error", exitCode: 1)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "error")
    }

    func testProcessResultLargeOutput() {
        let largeOutput = String(repeating: "x", count: 10000)
        let result = ProcessResult(stdout: largeOutput, stderr: "", exitCode: 0)
        XCTAssertEqual(result.stdout.count, 10000)
    }

    func testProcessResultNegativeExitCode() {
        let result = ProcessResult(stdout: "", stderr: "killed", exitCode: -9)
        XCTAssertEqual(result.exitCode, -9)
    }

    func testLockedDataAppend() {
        let locked = LockedData()
        let data1 = Data([0x01, 0x02])
        let data2 = Data([0x03, 0x04])
        locked.append(data1)
        locked.append(data2)
        let result = locked.getData()
        XCTAssertEqual(result, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func testLockedDataThreadSafety() {
        let locked = LockedData()
        let expectation = self.expectation(description: "Concurrent appends")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            DispatchQueue.global().async {
                let data = Data([UInt8(i)])
                locked.append(data)
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
        let result = locked.getData()
        XCTAssertEqual(result.count, 10)
    }
}
