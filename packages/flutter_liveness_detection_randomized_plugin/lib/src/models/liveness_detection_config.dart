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

  /// Consecutive out-of-oval (or no-face) frames before resetting countdown/UI.
  /// Ignores single-frame bounding-box jitter from the detector.
  final int faceOutOfOvalDebounceFrames;

  /// Bottom instruction while holding position before capture.
  final String delayedFaceCaptureInstruction;

  /// When true with [enableDelayedFaceCapture], shows a large animated countdown
  /// over the oval. When false, countdown text stays on the instruction card.
  final bool showAnimatedCaptureCountdown;

  /// When true (with mesh / standard detection), countdown only starts when eyes
  /// are not aimed down at the screen preview.
  final bool requireEyesTowardCamera;

  /// Shown when the face is in the oval but [requireEyesTowardCamera] fails.
  final String lookAtCameraInstruction;

  /// Wait after [takePicture] before reading the file (helps some Android devices).
  final int capturePostProcessDelayMs;

  /// Max dimension for MediaPipe face detection (lower = faster).
  final int faceDetectionMaxDim;

  /// MediaPipe mode: [fast] = bbox only; [standard] = bbox + mesh for blink/smile.
  final bool faceDetectionFastMode;

  /// When true, emits [LivenessFaceDetection] logs for debugging on device.
  final bool enableFaceDetectionLogging;

  /// Log a detection summary every N processed frames (state changes always log).
  final int faceDetectionLogIntervalFrames;

  LivenessDetectionConfig({
    this.startWithInfoScreen = false,
    this.durationLivenessVerify = 45,
    this.showDurationUiText = false,
    this.useCustomizedLabel = false,
    this.customizedLabel,
    this.isEnableMaxBrightness = true,
    this.imageQuality = 100,
    this.cameraResolution = ResolutionPreset.medium,
    this.enableCooldownOnFailure = false,
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
    this.faceOutOfOvalDebounceFrames = 3,
    this.delayedFaceCaptureInstruction =
        'Keep your head in the oval.\nLook at the camera at the top of your phone, not the screen.',
    this.showAnimatedCaptureCountdown = false,
    this.requireEyesTowardCamera = false,
    this.lookAtCameraInstruction =
        'Look at the camera at the top of your phone, not the screen',
    this.capturePostProcessDelayMs = 0,
    this.faceDetectionMaxDim = 320,
    this.faceDetectionFastMode = true,
    this.enableFaceDetectionLogging = false,
    this.faceDetectionLogIntervalFrames = 30,
  }) : assert(
         !useCustomizedLabel || customizedLabel != null,
         'customizedLabel must not be null when useCustomizedLabel is true',
       ),
       assert(manualSnapAfterSeconds >= 0, 'manualSnapAfterSeconds must be >= 0'),
       assert(delayedFaceCaptureAfterSeconds >= 0, 'delayedFaceCaptureAfterSeconds must be >= 0'),
       assert(
         !enableDelayedFaceCapture || delayedFaceCaptureStableFrames >= 1,
         'delayedFaceCaptureStableFrames must be >= 1 when enableDelayedFaceCapture is true',
       ),
       assert(
         faceOutOfOvalDebounceFrames >= 1,
         'faceOutOfOvalDebounceFrames must be >= 1',
       ),
       assert(faceDetectionMaxDim >= 128, 'faceDetectionMaxDim must be >= 128'),
       assert(
         faceDetectionLogIntervalFrames >= 1,
         'faceDetectionLogIntervalFrames must be >= 1',
       ),
       assert(
         capturePostProcessDelayMs >= 0,
         'capturePostProcessDelayMs must be >= 0',
       );
}
