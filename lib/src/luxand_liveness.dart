import 'package:flutter_liveness_detection_randomized_plugin/index.dart';
import 'models/luxand_liveness_result.dart';
import 'services/luxand_api.dart';

class LuxandLiveness {
  LuxandLiveness._();

  /// Runs the full liveness flow:
  /// 1. Launches face challenge screen (blink + smile).
  /// 2. Sends the captured image to the Luxand Cloud API.
  /// 3. Returns a [LuxandLivenessResult], or `null` if the user cancelled.
  ///
  /// [apiKey]  – your Luxand Cloud API token.
  /// [theme]   – optional UI customisation; falls back to a dark purple theme.
  static Future<LuxandLivenessResult?> verify({
    required BuildContext context,
    required String apiKey,
    LivenessDetectionTheme? theme,
  }) async {
    final effectiveTheme = theme ??
        const LivenessDetectionTheme(
          backgroundColor: Color(0xFF0A0A0A),
          ringProgressColor: Colors.deepPurple,
          ringTrackColor: Color(0xFF2A2A2A),
          instructionCardColor: Color(0xFF1A1A2E),
          instructionTextColor: Colors.white,
          instructionFontSize: 22,
          statusTextColor: Colors.white70,
          faceFoundLabel: 'Face detected — follow the instructions',
          faceNotFoundLabel: 'Position your face in the frame',
          backLabel: 'Cancel',
        );

    // Step 1: Run liveness challenges
    final String? capturedImagePath = await FlutterLivenessDetectionRandomizedPlugin
        .instance
        .livenessDetection(
      context: context,
      config: LivenessDetectionConfig(
        cameraResolution: ResolutionPreset.high,
        imageQuality: 90,
        isEnableMaxBrightness: true,
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
        enableCooldownOnFailure: true,
        maxFailedAttempts: 3,
        cooldownMinutes: 10,
        showDurationUiText: true,
        showCurrentStep: true,
        theme: effectiveTheme,
      ),
    );

    // User cancelled
    if (capturedImagePath == null) return null;

    // Step 2: Verify with Luxand Cloud API
    try {
      final imageFile = File(capturedImagePath);
      final api = LuxandApi(apiKey: apiKey);
      final response = await api.checkLiveness(imageFile);

      return LuxandLivenessResult.success(
        isReal: response.isReal,
        score: response.score,
        imageFile: imageFile,
      );
    } catch (e) {
      return LuxandLivenessResult.failure(e.toString());
    }
  }
}
