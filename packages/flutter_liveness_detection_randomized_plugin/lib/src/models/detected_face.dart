import 'dart:ui';

/// Platform-agnostic face detection result (replaces ML Kit [Face]).
class DetectedFace {
  final Rect boundingBox;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;
  final double? headEulerAngleX;
  final double? headEulerAngleY;

  const DetectedFace({
    required this.boundingBox,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.headEulerAngleX,
    this.headEulerAngleY,
  });
}
