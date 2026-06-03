import 'package:flutter/services.dart';

/// Flutter-side controller for the native camera capture pipeline.
///
/// The native side owns the camera and (later) the MediaPipe face detection.
/// Flutter receives:
///   - a `textureId` to render the live preview via a [Texture] widget, and
///   - (later) a stream of face-detection results for the oval gating logic.
///
/// All UI (oval, countdown, buttons) stays in Flutter and is drawn on top of
/// the [Texture]. The native layer never draws UI.
///
/// Channels (must stay in sync with Android/iOS):
///   - method : 'flutter_liveness_detection_randomized_plugin/native_capture'
///   - events : 'flutter_liveness_detection_randomized_plugin/native_capture/events'
class NativeCaptureController {
  static const MethodChannel _channel = MethodChannel(
    'flutter_liveness_detection_randomized_plugin/native_capture',
  );
  static const EventChannel _events = EventChannel(
    'flutter_liveness_detection_randomized_plugin/native_capture/events',
  );

  bool _initialized = false;
  NativePreview? _preview;

  /// The live preview description (texture id + native frame size). Null until
  /// [initialize] succeeds.
  NativePreview? get preview => _preview;
  bool get isInitialized => _initialized;

  /// Starts the native camera and returns the preview descriptor.
  ///
  /// [faceDetectionMaxDim] mirrors the Dart-side config so native detection
  /// (added in the next step) downscales frames the same way.
  Future<NativePreview> initialize({
    bool useFrontCamera = true,
    int faceDetectionMaxDim = 320,
    bool fastMode = true,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'initialize',
      <String, dynamic>{
        'useFrontCamera': useFrontCamera,
        'faceDetectionMaxDim': faceDetectionMaxDim,
        'fastMode': fastMode,
      },
    );
    if (result == null) {
      throw const NativeCaptureException('initialize returned null');
    }
    final preview = NativePreview.fromMap(result);
    _preview = preview;
    _initialized = true;
    return preview;
  }

  /// Stream of face-detection results from the native detector.
  ///
  /// Wired in the detection step; the preview-only slice does not emit yet.
  Stream<NativeFaceDetection> detections() {
    return _events.receiveBroadcastStream().map(
          (dynamic e) =>
              NativeFaceDetection.fromMap(Map<String, dynamic>.from(e as Map)),
        );
  }

  /// Captures a full-resolution JPEG and returns its absolute file path.
  Future<String> capture() async {
    final path = await _channel.invokeMethod<String>('capture');
    if (path == null) {
      throw const NativeCaptureException('capture returned no path');
    }
    return path;
  }

  Future<void> dispose() async {
    _initialized = false;
    _preview = null;
    await _channel.invokeMethod<void>('dispose');
  }
}

/// Describes the running native preview.
class NativePreview {
  /// Flutter texture id to render with a [Texture] widget.
  final int textureId;

  /// Native frame buffer dimensions (in the texture's raw/buffer orientation,
  /// before [rotationDegrees] is applied).
  final int width;
  final int height;

  /// Clockwise rotation (0/90/180/270) needed to make the buffer upright.
  final int rotationDegrees;

  /// Whether the preview is horizontally mirrored (front camera).
  final bool mirror;

  const NativePreview({
    required this.textureId,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.mirror,
  });

  double get aspectRatio => height == 0 ? 1 : width / height;

  factory NativePreview.fromMap(Map<String, dynamic> map) {
    return NativePreview(
      textureId: (map['textureId'] as num).toInt(),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
      mirror: map['mirror'] as bool? ?? false,
    );
  }
}

/// A single face-detection result from the native detector.
///
/// The bounding box is in native frame coordinates ([imageWidth] x
/// [imageHeight], upright). Flutter maps it onto the oval the same way the old
/// Dart pipeline did, so the in-oval behavior is unchanged.
class NativeFaceDetection {
  final bool hasFace;
  final double left;
  final double top;
  final double boxWidth;
  final double boxHeight;
  final int imageWidth;
  final int imageHeight;
  final bool mirror;

  const NativeFaceDetection({
    required this.hasFace,
    required this.left,
    required this.top,
    required this.boxWidth,
    required this.boxHeight,
    required this.imageWidth,
    required this.imageHeight,
    required this.mirror,
  });

  double get centerX => left + boxWidth / 2;
  double get centerY => top + boxHeight / 2;

  factory NativeFaceDetection.fromMap(Map<String, dynamic> map) {
    return NativeFaceDetection(
      hasFace: map['hasFace'] as bool? ?? false,
      left: (map['left'] as num?)?.toDouble() ?? 0,
      top: (map['top'] as num?)?.toDouble() ?? 0,
      boxWidth: (map['width'] as num?)?.toDouble() ?? 0,
      boxHeight: (map['height'] as num?)?.toDouble() ?? 0,
      imageWidth: (map['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (map['imageHeight'] as num?)?.toInt() ?? 0,
      mirror: map['mirror'] as bool? ?? false,
    );
  }
}

class NativeCaptureException implements Exception {
  final String message;
  const NativeCaptureException(this.message);
  @override
  String toString() => 'NativeCaptureException: $message';
}
