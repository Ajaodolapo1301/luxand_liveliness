import 'package:camera/camera.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/models/liveness_detection_label_model.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/models/liveness_detection_theme.dart';

class LivenessDetectionConfig {
  final bool startWithInfoScreen;
  final int? durationLivenessVerify;
  final bool showDurationUiText;
  final bool useCustomizedLabel;
  final LivenessDetectionLabelModel? customizedLabel;
  final bool isEnableMaxBrightness;
  final int imageQuality;
  final ResolutionPreset cameraResolution;
  final bool enableCooldownOnFailure;
  final int maxFailedAttempts;
  final int cooldownMinutes;
  final bool isEnableSnackBar;
  final bool shuffleListWithSmileLast;
  final bool showCurrentStep;
  final bool isDarkMode;

  /// Optional theme — overrides colors and labels. When null, falls back to
  /// the legacy [isDarkMode] toggle (black vs white).
  final LivenessDetectionTheme? theme;

  /// Optional manual fallback. When enabled, shows a "Snap" button after
  /// [manualSnapAfterSeconds] that captures a photo and proceeds.
  final bool enableManualSnapFallback;

  /// Seconds spent on the detection screen before showing the manual snap CTA.
  final int manualSnapAfterSeconds;

  /// Label for the manual snap button.
  final String manualSnapLabel;

  /// If true, the Snap button is disabled until a face is detected.
  final bool manualSnapRequireFaceDetected;

  /// When true, skips challenge steps. After the face is stable in the oval for
  /// [delayedFaceCaptureStableFrames] detections, waits [delayedFaceCaptureAfterSeconds]
  /// then captures **one** photo if the face is still detected.
  final bool enableDelayedFaceCapture;

  /// Whole seconds to wait after a stable face before taking the photo.
  final int delayedFaceCaptureAfterSeconds;

  /// Consecutive in-oval face frames required before the wait starts.
  final int delayedFaceCaptureStableFrames;

  /// Bottom instruction while holding position (countdown is appended when active).
  final String delayedFaceCaptureInstruction;

  LivenessDetectionConfig({
    this.startWithInfoScreen = false,
    this.durationLivenessVerify = 45,
    this.showDurationUiText = false,
    this.useCustomizedLabel = false,
    this.customizedLabel,
    this.isEnableMaxBrightness = true,
    this.imageQuality = 100,
    this.cameraResolution = ResolutionPreset.high,
    this.enableCooldownOnFailure = true,
    this.maxFailedAttempts = 3,
    this.cooldownMinutes = 10,
    this.isEnableSnackBar = true,
    this.shuffleListWithSmileLast = true,
    this.showCurrentStep = false,
    this.isDarkMode = true,
    this.theme,
    this.enableManualSnapFallback = false,
    this.manualSnapAfterSeconds = 10,
    this.manualSnapLabel = 'Snap',
    this.manualSnapRequireFaceDetected = true,
    this.enableDelayedFaceCapture = false,
    this.delayedFaceCaptureAfterSeconds = 3,
    this.delayedFaceCaptureStableFrames = 2,
    this.delayedFaceCaptureInstruction = 'Keep your head in the frame',
  }) : assert(
         !useCustomizedLabel || customizedLabel != null,
         'customizedLabel must not be null when useCustomizedLabel is true',
       ),
       assert(manualSnapAfterSeconds >= 0, 'manualSnapAfterSeconds must be >= 0'),
       assert(delayedFaceCaptureAfterSeconds >= 0, 'delayedFaceCaptureAfterSeconds must be >= 0'),
       assert(
         !enableDelayedFaceCapture || delayedFaceCaptureStableFrames >= 1,
         'delayedFaceCaptureStableFrames must be >= 1 when enableDelayedFaceCapture is true',
       );
}
