import XCTest
@testable import ScannerScheduling

final class ScanFrameGateTests: XCTestCase {
    func testOnlyOneFrameCanBeInFlight() throws {
        var gate = ScanFrameGate()
        let token = try XCTUnwrap(gate.begin(at: 1, interval: 0))
        XCTAssertNil(gate.begin(at: 100, interval: 0))
        XCTAssertTrue(gate.finish(token))
        XCTAssertNotNil(gate.begin(at: 100, interval: 0))
    }

    func testNormalModeWaitsForTheDetectionInterval() throws {
        var gate = ScanFrameGate()
        let token = try XCTUnwrap(gate.begin(at: 1, interval: 0.25))
        XCTAssertTrue(gate.finish(token))
        XCTAssertNil(gate.begin(at: 1.249, interval: 0.25))
        XCTAssertNotNil(gate.begin(at: 1.25, interval: 0.25))
    }

    func testUnrestrictedModeCanAcceptTheNextFrameImmediately() throws {
        var gate = ScanFrameGate()
        let token = try XCTUnwrap(gate.begin(at: 1, interval: 0))
        XCTAssertTrue(gate.finish(token))
        XCTAssertNotNil(gate.begin(at: 1, interval: 0))
    }

    func testStopDiscardsAnOutstandingResult() throws {
        var gate = ScanFrameGate()
        let token = try XCTUnwrap(gate.begin(at: 1, interval: 0.25))
        gate.reset()
        XCTAssertFalse(gate.finish(token))
    }

    func testRestartDoesNotInheritTheOldBusyStateOrTimeout() throws {
        var gate = ScanFrameGate()
        let old = try XCTUnwrap(gate.begin(at: 1, interval: 100))
        gate.reset()
        let current = try XCTUnwrap(gate.begin(at: 1.01, interval: 0.25))
        XCTAssertNotEqual(old, current)
        XCTAssertFalse(gate.finish(old))
        XCTAssertNil(gate.begin(at: 2, interval: 0))
        XCTAssertTrue(gate.finish(current))
        XCTAssertNotNil(gate.begin(at: 2, interval: 0))
    }

    func testRepeatedOldCompletionCannotReleaseANewerFrame() throws {
        var gate = ScanFrameGate()
        let old = try XCTUnwrap(gate.begin(at: 1, interval: 0))
        XCTAssertTrue(gate.finish(old))
        let current = try XCTUnwrap(gate.begin(at: 2, interval: 0))
        XCTAssertFalse(gate.finish(old))
        XCTAssertNil(gate.begin(at: 3, interval: 0))
        XCTAssertTrue(gate.finish(current))
    }
}
