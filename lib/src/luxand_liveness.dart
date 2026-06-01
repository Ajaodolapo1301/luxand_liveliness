import 'package:flutter/foundation.dart';
import 'package:flutter_liveness_detection_randomized_plugin/index.dart';

import 'debug/liveness_capture_exporter.dart';
import 'models/luxand_liveness_result.dart';
import 'services/luxand_api.dart';

class LuxandLiveness {
  LuxandLiveness._();

  /// 1. Launches face challenge screen (blink + smile).
  /// 2. Sends the captured image to the Luxand Cloud API.
  /// 3. Returns a [LuxandLivenessResult], or `null` if the user cancelled.
  ///
  /// [apiKey]  – your Luxand Cloud API token.
  /// [theme]   – optional UI customisation; falls back to a dark purple theme.
  ///
  /// [enableManualSnapFallback] – when `true`, after [manualSnapAfterSeconds]
  /// the bottom instruction card shows **Snap** (tap to capture) instead of
  /// the challenge text, for users who struggle on their device. Defaults to
  /// `false`.
  ///
  /// [enableDelayedFaceCapture] – when `true`, skips challenges: once the face
  /// is stable in the oval, waits [delayedFaceCaptureAfterSeconds] then takes
  /// one photo (timer resets if the face leaves the oval).
  ///
  /// [faceDetectionFastMode] – when `true`, uses MediaPipe fast mode (bbox only).
  /// Ignored while [requireEyesTowardCamera] is `true` (mesh is required).
  ///
  /// [faceOutOfOvalDebounceFrames] – consecutive bad frames before the capture
  /// countdown resets (default 3). Reduces jitter from noisy bounding boxes.
  ///
  /// [showAnimatedCaptureCountdown] – with [enableDelayedFaceCapture], shows a
  /// large animated 3-2-1 over the oval (default `true`). Set `false` for the
  /// legacy small countdown text on the instruction card.
  ///
  /// [requireEyesTowardCamera] – when `true` with delayed capture, requires eyes
  /// toward the lens (not down at the screen) before countdown and shutter.
  ///
  /// [enableMaxBrightness] – forces app brightness to 100% during capture.
  /// Default `false` to reduce screen glare in the eyes on bright AMOLED phones.
  ///
  /// [capturePostProcessDelayMs] – wait after [takePicture] before processing.
  /// Defaults to 200 ms on Android, 0 on iOS.
  ///
  /// [debugExportCaptures] – copies raw + Luxand upload JPEGs to Downloads/
  /// `luxand_liveness_debug` (visible in Samsung My Files). Defaults to `true`
  /// in debug builds only.
  static Future<LuxandLivenessResult?> verify({
    required BuildContext context,
    required String apiKey,
    LivenessDetectionTheme? theme,
    bool enableManualSnapFallback = false,
    int manualSnapAfterSeconds = 10,
    String manualSnapLabel = 'Snap',
    bool manualSnapRequireFaceDetected = true,
    bool enableDelayedFaceCapture = false,
    int delayedFaceCaptureAfterSeconds = 3,
    int delayedFaceCaptureStableFrames = 2,
    String? delayedFaceCaptureInstruction,
    bool faceDetectionFastMode = true,
    int faceOutOfOvalDebounceFrames = 3,
    bool showAnimatedCaptureCountdown = true,
    bool requireEyesTowardCamera = true,
    bool enableMaxBrightness = false,
    int? capturePostProcessDelayMs,
    bool? debugExportCaptures,
  }) async {
    final exportCaptures = debugExportCaptures ?? kDebugMode;

    final instruction = delayedFaceCaptureInstruction ??
        'Keep your head in the oval.\n'
            'Look at the camera at the top of your phone, not the screen.';

    final effectiveTheme = theme ??
        LivenessDetectionTheme(
          backgroundColor: const Color(0xFF0A0A0A),
          ringProgressColor: Colors.deepPurple,
          ringTrackColor: const Color(0xFF2A2A2A),
          instructionCardColor: const Color(0xFF1A1A2E),
          instructionTextColor: Colors.white,
          instructionFontSize: 14,
          statusTextColor: Colors.white70,
          faceFoundLabel: enableDelayedFaceCapture
              ? 'Face in frame — look at the camera at the top'
              : 'Face detected — follow the instructions',
          faceNotFoundLabel: enableDelayedFaceCapture
              ? 'Position your face in the oval'
              : 'Position your face in the frame',
          backLabel: 'Cancel',
        );

    final postDelay = capturePostProcessDelayMs ??
        (Platform.isAndroid ? 200 : 0);

    // Step 1: Run liveness challenges
    final String? capturedImagePath =
        await FlutterLivenessDetectionRandomizedPlugin.instance
            .livenessDetection(
              context: context,
              config: LivenessDetectionConfig(
                enableCooldownOnFailure: false,
                cameraResolution: ResolutionPreset.high,
                imageQuality: 90,
                isEnableMaxBrightness: enableMaxBrightness,
                durationLivenessVerify: 45,
                shuffleListWithSmileLast: false,
                useCustomizedLabel: true,
                customizedLabel: LivenessDetectionLabelModel(
                  blink: 'Blink 2-3 times',
                  smile: 'Smile',
                  lookLeft: '',
                  lookRight: '',
                  lookUp: '',
                  lookDown: '',
                ),
                showDurationUiText: true,
                showCurrentStep: true,
                theme: effectiveTheme,
                enableManualSnapFallback: enableManualSnapFallback,
                manualSnapAfterSeconds: manualSnapAfterSeconds,
                manualSnapLabel: manualSnapLabel,
                manualSnapRequireFaceDetected: manualSnapRequireFaceDetected,
                enableDelayedFaceCapture: enableDelayedFaceCapture,
                delayedFaceCaptureAfterSeconds: delayedFaceCaptureAfterSeconds,
                delayedFaceCaptureStableFrames: delayedFaceCaptureStableFrames,
                delayedFaceCaptureInstruction: instruction,
                lookAtCameraInstruction:
                    'Look at the camera at the top of your phone, not the screen',
                faceDetectionFastMode: faceDetectionFastMode,
                faceOutOfOvalDebounceFrames: faceOutOfOvalDebounceFrames,
                showAnimatedCaptureCountdown: showAnimatedCaptureCountdown,
                requireEyesTowardCamera:
                    enableDelayedFaceCapture && requireEyesTowardCamera,
                capturePostProcessDelayMs: postDelay,
              ),
            );

    // User cancelled
    if (capturedImagePath == null) return null;

    final imageFile = File(capturedImagePath);

    // Step 2: Verify with Luxand Cloud API
    try {
      final api = LuxandApi(apiKey: apiKey);
      final response = await api.checkLiveness(imageFile);

      if (exportCaptures) {
        await LivenessCaptureExporter.export(rawCapturePath: capturedImagePath);
      }

      return LuxandLivenessResult.success(
        isReal: response.isReal,
        score: response.score,
        imageFile: imageFile,
      );
    } catch (e) {
      if (exportCaptures) {
        await LivenessCaptureExporter.export(rawCapturePath: capturedImagePath);
      }
      return LuxandLivenessResult.failure(e.toString());
    }
  }
}
