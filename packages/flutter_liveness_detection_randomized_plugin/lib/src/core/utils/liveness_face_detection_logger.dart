import 'dart:developer' as dev;

/// Filter device logs with: `LivenessFaceDetection`
class LivenessFaceDetectionLogger {
  LivenessFaceDetectionLogger({this.enabled = true});

  static const logName = 'LivenessFaceDetection';

  bool enabled;
  int _frameCount = 0;
  bool? _lastFaceInOval;

  void info(String message) {
    if (!enabled) return;
    dev.log(message, name: logName);
  }

  void error(String message, [Object? error]) {
    if (!enabled) return;
    dev.log(
      error == null ? message : '$message — $error',
      name: logName,
      level: 1000,
    );
  }

  /// Logs every [intervalFrames] frames, or immediately when [faceInOval] changes.
  void logDetectionFrame({
    required int faceCount,
    required bool faceInOval,
    required int intervalFrames,
    String? bbox,
    String? metrics,
    String? extras,
  }) {
    if (!enabled) return;

    _frameCount++;
    final stateChanged = _lastFaceInOval != faceInOval;
    _lastFaceInOval = faceInOval;

    if (!stateChanged && _frameCount % intervalFrames != 0) return;

    final prefix = stateChanged ? 'STATE' : 'frame#$_frameCount';
    final parts = <String>[
      prefix,
      'faces=$faceCount',
      'inOval=$faceInOval',
      if (bbox != null) bbox,
      if (metrics != null) metrics,
      if (extras != null) extras,
    ];
    info(parts.join(' | '));
  }

  void resetFrameState() {
    _frameCount = 0;
    _lastFaceInOval = null;
  }
}
