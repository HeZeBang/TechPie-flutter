import CoreVideo
import XCTest
@testable import ScannerScheduling

final class PreviewFrameBufferTests: XCTestCase {
    private func makeFrame(width: Int) throws -> CVPixelBuffer {
        var frame: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, 16, kCVPixelFormatType_32BGRA, nil, &frame
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(frame)
    }

    func testReplacementReturnsTheNewFrame() throws {
        let slot = PreviewFrameBuffer()
        XCTAssertNil(slot.copyPixelBuffer())
        slot.replace(try makeFrame(width: 16))
        let first = try XCTUnwrap(slot.copyPixelBuffer()).takeRetainedValue()
        slot.replace(try makeFrame(width: 32))
        let second = try XCTUnwrap(slot.copyPixelBuffer()).takeRetainedValue()
        XCTAssertEqual(CVPixelBufferGetWidth(first), 16)
        XCTAssertEqual(CVPixelBufferGetWidth(second), 32)
    }

    func testRasterSnapshotRemainsValidAfterCameraClearsTheSlot() throws {
        let slot = PreviewFrameBuffer()
        slot.replace(try makeFrame(width: 32))
        let snapshot = try XCTUnwrap(slot.copyPixelBuffer()).takeRetainedValue()
        slot.replace(nil)
        XCTAssertNil(slot.copyPixelBuffer())
        XCTAssertEqual(CVPixelBufferGetWidth(snapshot), 32)
        XCTAssertEqual(CVPixelBufferGetHeight(snapshot), 16)
    }

}
