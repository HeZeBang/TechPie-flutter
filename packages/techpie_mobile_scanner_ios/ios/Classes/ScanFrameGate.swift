// Accessed on the main queue, alongside camera lifecycle and preview callbacks.
struct ScanFrameGate {
    private var serial: UInt64 = 0
    private var active: UInt64?
    private var nextScanTime = 0.0

    mutating func begin(at now: Double, interval: Double) -> UInt64? {
        guard active == nil, now >= nextScanTime else { return nil }
        serial &+= 1
        active = serial
        nextScanTime = now + max(0, interval)
        return serial
    }

    mutating func finish(_ token: UInt64) -> Bool {
        guard active == token else { return false }
        active = nil
        return true
    }

    mutating func reset() {
        active = nil
        nextScanTime = 0
    }
}
