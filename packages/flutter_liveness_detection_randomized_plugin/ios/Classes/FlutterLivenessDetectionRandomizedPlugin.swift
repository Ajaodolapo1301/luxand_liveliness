import Flutter
import UIKit

public class FlutterLivenessDetectionRandomizedPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let textureRegistry: FlutterTextureRegistry
    private var cameraController: NativeCameraController?
    private var detectionSink: FlutterEventSink?

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_liveness_detection_randomized_plugin",
            binaryMessenger: registrar.messenger())
        let instance = FlutterLivenessDetectionRandomizedPlugin(
            textureRegistry: registrar.textures())
        registrar.addMethodCallDelegate(instance, channel: channel)

        let captureChannel = FlutterMethodChannel(
            name: "flutter_liveness_detection_randomized_plugin/native_capture",
            binaryMessenger: registrar.messenger())
        captureChannel.setMethodCallHandler { call, result in
            instance.onNativeCaptureCall(call, result: result)
        }

        let eventChannel = FlutterEventChannel(
            name: "flutter_liveness_detection_randomized_plugin/native_capture/events",
            binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    private func onNativeCaptureCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            let args = call.arguments as? [String: Any]
            let useFront = args?["useFrontCamera"] as? Bool ?? true
            let controller = NativeCameraController(registry: textureRegistry)
            cameraController = controller
            controller.initialize(useFrontCamera: useFront, result: result)
        case "capture":
            // Next step: trigger a still capture and return the JPEG path.
            result(FlutterError(code: "not_implemented",
                                message: "Native capture is not implemented yet.", details: nil))
        case "dispose":
            cameraController?.dispose()
            cameraController = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler (detection events; wired in the detection step)

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError? {
        detectionSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        detectionSink = nil
        return nil
    }
}
