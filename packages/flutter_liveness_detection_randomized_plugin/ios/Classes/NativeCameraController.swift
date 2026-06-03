import AVFoundation
import Flutter

/// Owns an AVCaptureSession preview rendered into a Flutter texture.
///
/// Scope of this slice: live preview only. Frames stay native; Flutter renders
/// the texture and draws its existing oval overlay on top. MediaPipe detection
/// and still capture are added in later steps.
///
/// The video connection is rotated to portrait natively, so `rotationDegrees`
/// is reported as 0 and only the front-camera `mirror` flag is left for Dart to
/// apply — keeping the Dart transform logic identical across platforms.
class NativeCameraController: NSObject, FlutterTexture,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    private let registry: FlutterTextureRegistry
    private var textureId: Int64 = -1

    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(label: "native_capture.sample")
    private let bufferLock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    private var initResult: FlutterResult?
    private var hasReplied = false
    private var useFrontCamera = true

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }

    func initialize(useFrontCamera: Bool, result: @escaping FlutterResult) {
        self.useFrontCamera = useFrontCamera
        self.initResult = result

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(result: result)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndStart(result: result)
                } else {
                    self?.replyError(result, "camera_permission_denied", "Camera permission denied")
                }
            }
        default:
            replyError(result, "camera_permission_denied", "Camera permission denied")
        }
    }

    private func configureAndStart(result: @escaping FlutterResult) {
        sampleQueue.async { [weak self] in
            guard let self = self else { return }

            self.textureId = self.registry.register(self)

            let position: AVCaptureDevice.Position = self.useFrontCamera ? .front : .back
            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: position),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                self.replyError(result, "camera_init_failed", "No camera device available")
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if self.session.canAddInput(input) { self.session.addInput(input) }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.sampleQueue)
            if self.session.canAddOutput(output) { self.session.addOutput(output) }

            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // Leave mirroring to Dart so the transform path matches Android.
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
            }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func dispose() {
        sampleQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            if self.textureId >= 0 {
                self.registry.unregisterTexture(self.textureId)
                self.textureId = -1
            }
            self.bufferLock.lock()
            self.latestPixelBuffer = nil
            self.bufferLock.unlock()
        }
    }

    // MARK: - FlutterTexture

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        bufferLock.lock()
        latestPixelBuffer = pixelBuffer
        bufferLock.unlock()

        if textureId >= 0 {
            registry.textureFrameAvailable(textureId)
        }

        if !hasReplied {
            hasReplied = true
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let result = initResult
            initResult = nil
            DispatchQueue.main.async {
                result?([
                    "textureId": self.textureId,
                    "width": width,
                    "height": height,
                    "rotationDegrees": 0,
                    "mirror": self.useFrontCamera,
                ])
            }
        }
    }

    // MARK: - Helpers

    private func replyError(_ result: @escaping FlutterResult, _ code: String, _ message: String) {
        guard !hasReplied else { return }
        hasReplied = true
        DispatchQueue.main.async {
            result(FlutterError(code: code, message: message, details: nil))
        }
    }
}
