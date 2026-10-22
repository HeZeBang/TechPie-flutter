import CoreVideo
import Foundation
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

    func testEmptySlotReturnsNoFrame() {
        XCTAssertNil(PreviewFrameBuffer().copyPixelBuffer())
    }

    func testReplacementReturnsTheNewFrame() throws {
        let slot = PreviewFrameBuffer()
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

    func testConcurrentReplacementClearingAndRetaining() throws {
        let slot = PreviewFrameBuffer()
        let frames = [try makeFrame(width: 16), try makeFrame(width: 32)]
        DispatchQueue.concurrentPerform(iterations: 10_000) { index in
            switch index % 3 {
            case 0:
                slot.replace(frames[index % frames.count])
            case 1:
                slot.replace(nil)
            default:
                if let snapshot = slot.copyPixelBuffer()?.takeRetainedValue() {
                    XCTAssertTrue([16, 32].contains(CVPixelBufferGetWidth(snapshot)))
                    XCTAssertEqual(CVPixelBufferGetHeight(snapshot), 16)
                }
            }
        }
    }
}
