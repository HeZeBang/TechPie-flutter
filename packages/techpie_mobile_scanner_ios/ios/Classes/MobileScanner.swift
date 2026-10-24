//
//  MobileScanner.swift
//  mobile_scanner
//
//  Created by Julian Steenbakker on 15/02/2022.
//

import Foundation
import Flutter
import AVFoundation
import CoreImage
import MLKitVision
import MLKitBarcodeScanning

typealias MobileScannerCallback = ((Array<Barcode>?, Error?, CGSize, Data?) -> ())
typealias TorchModeChangeCallback = ((Int?) -> ())
typealias ZoomScaleChangeCallback = ((Double?) -> ())
typealias PreviewFrameCallback = (() -> ())

public class MobileScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, FlutterTexture {
    /// Capture session of the camera
    var captureSession: AVCaptureSession?

    /// The selected camera
    var device: AVCaptureDevice!

    /// The long lived barcode scanner for scanning barcodes from a camera preview.
    var scanner: BarcodeScanner? = nil

    /// Default position of camera
    var videoPosition: AVCaptureDevice.Position = AVCaptureDevice.Position.back

    /// When results are found, this callback will be called
    let mobileScannerCallback: MobileScannerCallback

    /// When torch mode is changes, this callback will be called
    let torchModeChangeCallback: TorchModeChangeCallback

    /// When zoom scale is changes, this callback will be called
    let zoomScaleChangeCallback: ZoomScaleChangeCallback

    /// When the preview delivers its first frame after a start, this callback
    /// will be called — `start` only says the session was configured.
    let previewFrameCallback: PreviewFrameCallback

    /// Whether the current start has already reported its first frame.
    private var previewFrameSent = false

    /// If provided, the Flutter registry will be used to send the output of the CaptureOutput to a Flutter texture.
    private let registry: FlutterTextureRegistry?

    /// Shared by the main-queue camera callback and Flutter's raster thread.
    private let previewBuffer = PreviewFrameBuffer()

    /// Texture id of the camera preview for Flutter
    private var textureId: Int64!

    var detectionSpeed: DetectionSpeed = DetectionSpeed.noDuplicates

    private let backgroundQueue = DispatchQueue(label: "camera-handling")
    private let recognitionQueue = DispatchQueue(label: "barcode-recognition", qos: .userInitiated)
    // Only used by recognitionQueue, and only when returnImage is requested.
    private lazy var imageContext = CIContext()
    private var returnImage = false

    var standardZoomFactor: CGFloat = 1

    private var scanGate = ScanFrameGate()

    public var timeoutSeconds: Double = 0

    private var stopped: Bool {
        return device == nil || captureSession == nil
    }

    private var paused: Bool {
        return stopped && textureId != nil
    }

    init(registry: FlutterTextureRegistry?, mobileScannerCallback: @escaping MobileScannerCallback, torchModeChangeCallback: @escaping TorchModeChangeCallback, zoomScaleChangeCallback: @escaping ZoomScaleChangeCallback, previewFrameCallback: @escaping PreviewFrameCallback) {
        self.registry = registry
        self.mobileScannerCallback = mobileScannerCallback
        self.torchModeChangeCallback = torchModeChangeCallback
        self.zoomScaleChangeCallback = zoomScaleChangeCallback
        self.previewFrameCallback = previewFrameCallback
        super.init()
    }

    /// Get the default camera device for the given `position`.
    ///
    /// This function selects the most appropriate camera, when it is available.
    private func getDefaultCameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if #available(iOS 13.0, *) {
            // Find the built-in Triple Camera, if it exists.
            if let device = AVCaptureDevice.default(.builtInTripleCamera,
                                                    for: .video,
                                                    position: position) {
                return device
            }

            // Find the built-in Dual-Wide Camera, if it exists.
            if let device = AVCaptureDevice.default(.builtInDualWideCamera,
                                                    for: .video,
                                                    position: position) {
                return device
            }
        }

        // Find the built-in Dual Camera, if it exists.
        if let device = AVCaptureDevice.default(.builtInDualCamera,
                                                for: .video,
                                                position: position) {
            return device
        }

        // Find the built-in Wide-Angle Camera, if it exists.
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                for: .video,
                                                position: position) {
            return device
        }

        return nil
    }

    /// Check if we already have camera permission.
    func checkPermission() -> Int {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            return 0
        case .authorized:
            return 1
        default:
            return 2
        }
    }

    /// Request permissions for video
    func requestPermission(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
    }

    /// Gets called when a new image is added to the buffer
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        guard let textureId = textureId,
              captureSession?.outputs.contains(where: { $0 === output }) == true,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        previewBuffer.replace(imageBuffer)
        registry?.textureFrameAvailable(textureId)

        // The sample buffers only arrive once the session is running, so the
        // first one ends whatever the preview was showing before.
        if !previewFrameSent {
            previewFrameSent = true
            previewFrameCallback()
        }

        // Preview delivery never waits for recognition. Admit at most one frame
        // to the worker, so a slow detector cannot build a camera-buffer backlog.
        let interval = detectionSpeed == .normal ? timeoutSeconds : 0
        guard let scanner = scanner,
              let token = scanGate.begin(at: ProcessInfo.processInfo.systemUptime, interval: interval) else {
            return
        }
        let size = CGSize(width: CVPixelBufferGetWidth(imageBuffer),
                          height: CVPixelBufferGetHeight(imageBuffer))
        let orientation = imageOrientation(deviceOrientation: UIDevice.current.orientation,
                                           defaultOrientation: .portrait,
                                           position: videoPosition)
        let includeImage = returnImage

        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            // The sample buffer must remain alive until the synchronous detector
            // and any requested JPEG conversion have finished reading it.
            defer { withExtendedLifetime(sampleBuffer) {} }
            let result: Result<([Barcode], Data?), Error> = autoreleasepool {
                Result {
                    let image = VisionImage(buffer: sampleBuffer)
                    image.orientation = orientation
                    let barcodes = try scanner.results(in: image)
                    var bytes: Data?
                    if includeImage && !barcodes.isEmpty {
                        bytes = imageBuffer.image(using: self.imageContext)?.jpegData(compressionQuality: 0.8)
                    }
                    return (barcodes, bytes)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.scanGate.finish(token) else { return }
                switch result {
                case .failure(let error):
                    self.mobileScannerCallback(nil, error, size, nil)
                case .success(let (barcodes, bytes)):
                    if self.detectionSpeed == .noDuplicates {
                        let values = barcodes.compactMap { $0.rawValue }.sorted()
                        if self.barcodesString == values { return }
                        if !values.isEmpty { self.barcodesString = values }
                    }
                    self.mobileScannerCallback(barcodes, nil, size, bytes)
                }
            }
        }
    }

    /// Start scanning for barcodes
    func start(barcodeScannerOptions: BarcodeScannerOptions?, cameraPosition: AVCaptureDevice.Position, torch: Bool, detectionSpeed: DetectionSpeed, returnImage: Bool, completion: @escaping (MobileScannerStartParameters) -> ()) throws {
        self.detectionSpeed = detectionSpeed
        if (device != nil || captureSession != nil) {
            throw MobileScannerError.alreadyStarted
        }

        barcodesString = nil
        scanGate.reset()
        self.returnImage = returnImage
        scanner = barcodeScannerOptions != nil ? BarcodeScanner.barcodeScanner(options: barcodeScannerOptions!) : BarcodeScanner.barcodeScanner()
        captureSession = AVCaptureSession()
        // Every start reports its own first frame.
        previewFrameSent = false
        textureId = textureId ?? registry?.register(self)

        // Open the camera device
        device = getDefaultCameraDevice(position: cameraPosition)

        if (device == nil) {
            throw MobileScannerError.noCamera
        }

        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode), options: .new, context: nil)
        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor), options: .new, context: nil)

        // Check the zoom factor at switching from ultra wide camera to wide camera.
        standardZoomFactor = 1
        if #available(iOS 13.0, *) {
            for (index, actualDevice) in device.constituentDevices.enumerated() {
                if (actualDevice.deviceType != .builtInUltraWideCamera) {
                    if index > 0 && index <= device.virtualDeviceSwitchOverVideoZoomFactors.count {
                        standardZoomFactor = CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[index - 1])
                    }
                    break
                }
            }
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if #available(iOS 15.4, *) , device.isFocusModeSupported(.autoFocus){
                device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            }
            device.unlockForConfiguration()
        } catch {}

        captureSession!.beginConfiguration()

        // Add device input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession!.addInput(input)
        } catch {
            throw MobileScannerError.cameraError(error)
        }

        if captureSession!.canSetSessionPreset(.hd1280x720) {
            captureSession!.sessionPreset = .hd1280x720
        } else if captureSession!.canSetSessionPreset(.vga640x480) {
            captureSession!.sessionPreset = .vga640x480
        }
        // Add video output.
        let videoOutput = AVCaptureVideoDataOutput()

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        videoPosition = cameraPosition
        // calls captureOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)

        captureSession!.addOutput(videoOutput)
        for connection in videoOutput.connections {
            connection.videoOrientation = .portrait
            if cameraPosition == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        captureSession!.commitConfiguration()

        backgroundQueue.async {
            guard let captureSession = self.captureSession else {
                return
            }

            captureSession.startRunning()

            // After the capture session started, turn on the torch (if requested)
            // and reset the zoom scale back to the default.
            // Ensure that these adjustments are done on the main DispatchQueue,
            // as they interact with the hardware camera.
            if (torch) {
                DispatchQueue.main.async {
                    self.turnTorchOn()
                }
            }

            DispatchQueue.main.async {
                do {
                    try self.resetScale()
                } catch {
                    // If the zoom scale could not be reset,
                    // continue with the capture session anyway.
                }
            }

            if let device = self.device {
                // When querying the dimensions of the camera,
                // stay on the background thread,
                // as this does not change the configuration of the hardware camera.
                let dimensions = CMVideoFormatDescriptionGetDimensions(
                    device.activeFormat.formatDescription)

                completion(
                    MobileScannerStartParameters(
                        width: Double(dimensions.height),
                        height: Double(dimensions.width),
                        currentTorchState: device.hasTorch ? device.torchMode.rawValue : -1,
                        textureId: self.textureId ?? 0
                    )
                )

                return
            }

            completion(MobileScannerStartParameters())
        }
    }

    /// Pause scanning for barcodes
    func pause(force: Bool = false) throws {
        if (!force) {
            if (paused) {
                throw MobileScannerError.alreadyPaused
            } else if (stopped) {
                throw MobileScannerError.alreadyStopped
            }
        }
        releaseCamera()
    }

    /// Stop scanning for barcodes
    func stop(force: Bool = false) throws {
        if (!paused && stopped && !force) {
            throw MobileScannerError.alreadyStopped
        }
        releaseCamera()
        releaseTexture()
    }

    private func releaseCamera() {
        // A worker from the previous session must not publish into a restarted
        // camera or clear its in-flight state.
        scanGate.reset()
        guard let captureSession = captureSession else {
            return
        }

        guard let device = device else {
            return
        }

        captureSession.stopRunning()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        previewBuffer.replace(nil)
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode))
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor))
        self.captureSession = nil
        self.device = nil
    }

    private func releaseTexture() {
        if (textureId != nil) {
            registry?.unregisterTexture(textureId)
        }
        textureId = nil
        scanner = nil
    }

    /// Toggle the torch.
    ///
    /// This method should be called on the main DispatchQueue.
    func toggleTorch() {
        guard let device = self.device else {
            return
        }

        if (!device.hasTorch || !device.isTorchAvailable) {
            return
        }

        var newTorchMode: AVCaptureDevice.TorchMode = device.torchMode

        switch(device.torchMode) {
        case AVCaptureDevice.TorchMode.auto:
            newTorchMode = device.isTorchActive ? AVCaptureDevice.TorchMode.off : AVCaptureDevice.TorchMode.on
            break;
        case AVCaptureDevice.TorchMode.off:
            newTorchMode = AVCaptureDevice.TorchMode.on
            break;
        case AVCaptureDevice.TorchMode.on:
            newTorchMode = AVCaptureDevice.TorchMode.off
            break;
        default:
            return;
        }

        if (!device.isTorchModeSupported(newTorchMode) || device.torchMode == newTorchMode) {
            return;
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = newTorchMode
            device.unlockForConfiguration()
        } catch(_) {}
    }

    /// Turn the torch on.
    private func turnTorchOn() {
        guard let device = self.device else {
            return
        }

        if (!device.hasTorch || !device.isTorchAvailable || !device.isTorchModeSupported(.on) || device.torchMode == .on) {
            return
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = .on
            device.unlockForConfiguration()
        } catch(_) {}
    }

    // Observer for torch state
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case "torchMode":
            // Off = 0, On = 1, Auto = 2
            let state = change?[.newKey] as? Int
            torchModeChangeCallback(state)
        case "videoZoomFactor":
            let zoomFactor = change?[.newKey] as? CGFloat ?? 1
            let zoomScale = (zoomFactor - 1) / 4
            zoomScaleChangeCallback(Double(zoomScale))
        default:
            break
        }
    }

    /// Set the zoom factor of the camera
    func setScale(_ scale: CGFloat) throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }

        do {
            try device.lockForConfiguration()
            let maxZoomFactor = device.activeFormat.videoMaxZoomFactor

            var actualScale = (scale * 4) + 1

            // Set maximum zoomrate of 5x
            actualScale = min(5.0, actualScale)

            // Limit to max rate of camera
            actualScale = min(maxZoomFactor, actualScale)

            // Limit to 1.0 scale
            device.videoZoomFactor = actualScale
            device.unlockForConfiguration()
        } catch {
            throw MobileScannerError.zoomError(error)
        }

    }

    /// Reset the zoom factor of the camera
    func resetScale() throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = standardZoomFactor
            device.unlockForConfiguration()
        } catch {
            throw MobileScannerError.zoomError(error)
        }
    }

    /// Analyze a single image
    func analyzeImage(image: UIImage, position: AVCaptureDevice.Position,
                      barcodeScannerOptions: BarcodeScannerOptions?, callback: @escaping BarcodeScanningCallback) {
        let image = VisionImage(image: image)
        image.orientation = imageOrientation(
            deviceOrientation: UIDevice.current.orientation,
            defaultOrientation: .portrait,
            position: position
        )

        let scanner: BarcodeScanner = barcodeScannerOptions != nil ? BarcodeScanner.barcodeScanner(options: barcodeScannerOptions!) : BarcodeScanner.barcodeScanner()

        scanner.process(image, completion: callback)
    }

    var barcodesString: Array<String?>?

    /// Rotates images accordingly
    func imageOrientation(
        deviceOrientation: UIDeviceOrientation,
        defaultOrientation: UIDeviceOrientation,
        position: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
        switch deviceOrientation {
        case .portrait:
            return position == .front ? .leftMirrored : .right
        case .landscapeLeft:
            return position == .front ? .downMirrored : .up
        case .portraitUpsideDown:
            return position == .front ? .rightMirrored : .left
        case .landscapeRight:
            return position == .front ? .upMirrored : .down
        case .faceDown, .faceUp, .unknown:
            return .up
        @unknown default:
            return imageOrientation(deviceOrientation: defaultOrientation, defaultOrientation: .portrait, position: .back)
        }
    }

    /// Sends output of OutputBuffer to a Flutter texture
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        return previewBuffer.copyPixelBuffer()
    }

    struct MobileScannerStartParameters {
        var width: Double = 0.0
        var height: Double = 0.0
        var currentTorchState: Int = -1
        var textureId: Int64 = 0
    }
}
