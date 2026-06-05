import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as mp;
import 'package:flutter/services.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/core/utils/liveness_face_detection_logger.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/models/detected_face.dart';

/// MediaPipe BlazeFace via [face_detection_tflite] — replaces ML Kit for detection.
class MediaPipeFaceDetectorHelper {
  MediaPipeFaceDetectorHelper._();
  static final MediaPipeFaceDetectorHelper instance =
      MediaPipeFaceDetectorHelper._();

  mp.FaceDetector? _detector;
  Future<void>? _initFuture;
  bool logEnabled = false;
  int _diagFrame = 0;
  final LivenessFaceDetectionLogger _logger = LivenessFaceDetectionLogger();

  Future<void> ensureInitialized() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    _logger.enabled = logEnabled;
    try {
      final detector = mp.FaceDetector();
      await detector.initialize(model: mp.FaceDetectionModel.frontCamera);
      _detector = detector;
      _logger.info('FaceDetector ready (model=frontCamera)');
    } catch (e, st) {
      _logger.error('FaceDetector init failed', e);
      _logger.error('stack', st);
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _detector?.dispose();
    _detector = null;
    _initFuture = null;
  }

  /// Detects faces from a live camera frame. Runs off the UI thread inside the package.
  Future<List<DetectedFace>> processCameraImage(
    CameraImage image, {
    required CameraDescription camera,
    required DeviceOrientation deviceOrientation,
    mp.CameraFrameRotation? rotation,
    mp.FaceDetectionMode mode = mp.FaceDetectionMode.standard,
    int maxDim = 480,
  }) async {
    await ensureInitialized();
    final detector = _detector;
    if (detector == null) return [];

    try {
      final effectiveRotation = rotation ??
          mp.rotationForFrame(
            width: image.width,
            height: image.height,
            sensorOrientation: camera.sensorOrientation,
            isFrontCamera: camera.lensDirection == CameraLensDirection.front,
            deviceOrientation: deviceOrientation,
          );

      final faces = await detector.detectFacesFromCameraImage(
        image,
        mode: mode,
        rotation: effectiveRotation,
        maxDim: maxDim,
        // iOS feeds single-plane bgra8888. The package only auto-sets
        // isBgra=true on macOS, so without this it decodes iOS frames as RGBA
        // and swaps R/B → BlazeFace sees blue skin and detects nothing.
        // Ignored for Android's multi-plane YUV.
        isBgra: true,
      );

      // Throttled diagnostics: confirms frames arrive, their shape, the
      // rotation applied, and how many faces came back. Filter logs by
      // `LivenessFaceDetection`.
      _diagFrame++;
      if (logEnabled && _diagFrame % 15 == 1) {
        _logger.info(
          'detect | ${image.width}x${image.height} '
          'planes=${image.planes.length} '
          'bpr=${image.planes.isNotEmpty ? image.planes.first.bytesPerRow : -1} '
          'sensor=${camera.sensorOrientation} '
          'lens=${camera.lensDirection.name} '
          'rot=${effectiveRotation?.name ?? "none"} '
          'faces=${faces.length}',
        );
      }

      if (faces.isEmpty) return [];
      return faces.map(_mapFace).toList();
    } catch (e, st) {
      _logger.error('detectFacesFromCameraImage failed', e);
      _logger.error('stack', st);
      return [];
    }
  }

  DetectedFace _mapFace(mp.Face face) {
    final bb = face.boundingBox;
    final rect = Rect.fromLTRB(
      bb.topLeft.x,
      bb.topLeft.y,
      bb.bottomRight.x,
      bb.bottomRight.y,
    );

    final mesh = face.mesh;
    double? leftEye;
    double? rightEye;
    double? smile;

    bool? gazeTowardCamera;
    if (mesh != null && mesh.length >= 468) {
      final points = mesh.points;
      leftEye = _eyeOpenFromEar(_ear(points, _leftEarIndices));
      rightEye = _eyeOpenFromEar(_ear(points, _rightEarIndices));
      smile = _smileProbability(points, rect.width);
      gazeTowardCamera = _gazeTowardCamera(points);
    }

    return DetectedFace(
      boundingBox: rect,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
      smilingProbability: smile,
      gazeTowardCamera: gazeTowardCamera,
    );
  }

  /// Proxy: eyes looking down at the phone screen raise vertical ratio in the eye socket.
  static bool? _gazeTowardCamera(List<mp.Point> mesh) {
    final left = _eyeVerticalOpenRatio(
      mesh,
      top: 159,
      bottom: 145,
      outer: 33,
      inner: 133,
    );
    final right = _eyeVerticalOpenRatio(
      mesh,
      top: 386,
      bottom: 374,
      outer: 263,
      inner: 362,
    );
    if (left == null || right == null) return null;
    const maxDownwardRatio = 0.58;
    return left < maxDownwardRatio && right < maxDownwardRatio;
  }

  static double? _eyeVerticalOpenRatio(
    List<mp.Point> mesh, {
    required int top,
    required int bottom,
    required int outer,
    required int inner,
  }) {
    final topY = mesh[top].y;
    final bottomY = mesh[bottom].y;
    final span = bottomY - topY;
    if (span.abs() < 1e-3) return null;
    final centerY = (mesh[outer].y + mesh[inner].y) / 2;
    return (centerY - topY) / span;
  }

  static const _leftEarIndices = [33, 160, 158, 133, 153, 144];
  static const _rightEarIndices = [362, 385, 387, 263, 373, 380];

  static double _dist(mp.Point a, mp.Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Eye aspect ratio (EAR). Lower = more closed.
  static double _ear(List<mp.Point> mesh, List<int> indices) {
    final p = [for (final i in indices) mesh[i]];
    final vertical1 = _dist(p[1], p[5]);
    final vertical2 = _dist(p[2], p[4]);
    final horizontal = _dist(p[0], p[3]);
    if (horizontal < 1e-6) return 0.3;
    return (vertical1 + vertical2) / (2.0 * horizontal);
  }

  /// Maps EAR to 0–1 open probability (tuned for MediaPipe mesh).
  static double _eyeOpenFromEar(double ear) {
    return ((ear - 0.12) / 0.22).clamp(0.0, 1.0);
  }

  /// Smile proxy from mouth width vs face width.
  static double _smileProbability(List<mp.Point> mesh, double faceWidth) {
    if (faceWidth < 1) return 0;
    const mouthLeft = 61;
    const mouthRight = 291;
    final mouthWidth = _dist(mesh[mouthLeft], mesh[mouthRight]);
    final ratio = mouthWidth / faceWidth;
    return ((ratio - 0.38) / 0.12).clamp(0.0, 1.0);
  }
}
