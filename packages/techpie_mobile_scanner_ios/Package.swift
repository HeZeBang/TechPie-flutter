// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScannerScheduling",
    products: [.library(name: "ScannerScheduling", targets: ["ScannerScheduling"])],
    targets: [
        .target(
            name: "ScannerScheduling",
            path: "ios/Classes",
            exclude: [
                "BarcodeHandler.swift", "DetectionSpeed.swift", "MobileScanner.swift",
                "MobileScannerError.swift", "MobileScannerErrorCodes.swift",
                "MobileScannerPlugin.swift", "MobileScannerUtilities.swift",
            ],
            sources: ["ScanFrameGate.swift", "PreviewFrameBuffer.swift"]
        ),
        .testTarget(name: "ScannerSchedulingTests", dependencies: ["ScannerScheduling"]),
    ]
)
