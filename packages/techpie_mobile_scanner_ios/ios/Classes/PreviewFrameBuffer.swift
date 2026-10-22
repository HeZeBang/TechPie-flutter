import CoreVideo
import Foundation

/// Holds the latest frame until the raster thread takes its own retained copy.
final class PreviewFrameBuffer {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func replace(_ buffer: CVPixelBuffer?) {
        lock.lock()
        defer { lock.unlock() }
        latest = buffer
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = latest else { return nil }
        // Retain under the same lock as replacement and clearing.
        return Unmanaged.passRetained(buffer)
    }
}
