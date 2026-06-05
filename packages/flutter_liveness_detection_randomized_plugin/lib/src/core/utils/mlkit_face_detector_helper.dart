import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/core/utils/liveness_face_detection_logger.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/models/detected_face.dart';

/// Google ML Kit face detection — used for the iOS Dart capture path.
///
/// Why iOS uses ML Kit instead of the MediaPipe ([face_detection_tflite]) path:
/// the tflite package decodes iOS video-range NV12 with a full-range formula
/// (washed-out → zero detections) and the FFI runtime has an open release-build
/// symbol-stripping crash. ML Kit is Google's production-hardened detector.
///
/// Coordinate convention (correct-by-construction, no rotation math):
/// - `camera_avfoundation` pre-rotates the stream to PORTRAIT via the capture
///   connection, so the bgra8888 buffer arrives upright (e.g. 720x1280).
/// - ML Kit ignores [InputImageMetadata.rotation] on iOS, so the returned
///   bounding boxes are already in that upright portrait pixel space.
/// - The front camera is mirrored by AVFoundation, so callers pass
///   `mirrorHorizontally: false` and use `Size(image.width, image.height)` as
///   the detection-image size.
class MlKitFaceDetectorHelper {
  MlKitFaceDetectorHelper._();
  static final MlKitFaceDetectorHelper instance = MlKitFaceDetectorHelper._();

  FaceDetector? _detector;
  bool logEnabled = false;
  int _diagFrame = 0;
  final LivenessFaceDetectionLogger _logger = LivenessFaceDetectionLogger();

  Future<void> ensureInitialized() async {
    _logger.enabled = logEnabled;
    _detector ??= FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    _logger.info('ML Kit FaceDetector ready');
  }

  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
  }

  /// Detects faces from a live iOS bgra8888 frame. Returns an empty list (not an
  /// error) for unsupported frames or detection failures.
  Future<List<DetectedFace>> processCameraImage(
    CameraImage image, {
    required CameraDescription camera,
  }) async {
    await ensureInitialized();
    final detector = _detector;
    if (detector == null) return [];

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return [];

    try {
      final faces = await detector.processImage(inputImage);

      _diagFrame++;
      if (logEnabled && _diagFrame % 15 == 1) {
        _logger.info(
          'mlkit | ${image.width}x${image.height} '
          'planes=${image.planes.length} '
          'bpr=${image.planes.isNotEmpty ? image.planes.first.bytesPerRow : -1} '
          'fmt=${image.format.group.name} '
          'faces=${faces.length}',
        );
      }

      if (faces.isEmpty) return [];
      return faces.map(_mapFace).toList();
    } catch (e, st) {
      _logger.error('ML Kit processImage failed', e);
      _logger.error('stack', st);
      return [];
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // iOS delivers a single non-planar bgra8888 buffer. Rotation is ignored by
    // ML Kit on iOS, so pass 0deg; the buffer is already upright.
    if (image.format.group != ImageFormatGroup.bgra8888) return null;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  DetectedFace _mapFace(Face face) {
    final headX = face.headEulerAngleX;
    final headY = face.headEulerAngleY;
    return DetectedFace(
      boundingBox: face.boundingBox,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      headEulerAngleX: headX,
      headEulerAngleY: headY,
      gazeTowardCamera: _gazeTowardCamera(headX, headY),
    );
  }

  /// ML Kit has no eye-mesh, so "looking at the camera" is approximated from
  /// head pose: small yaw (Y, left/right) and pitch (X, up/down). This is a
  /// head-orientation proxy, not true eye gaze; thresholds are lenient and may
  /// need on-device tuning.
  static bool? _gazeTowardCamera(double? headX, double? headY) {
    if (headX == null || headY == null) return null;
    const double maxYawDeg = 18;
    const double maxPitchDeg = 15;
    return headY.abs() < maxYawDeg && headX.abs() < maxPitchDeg;
  }
}
