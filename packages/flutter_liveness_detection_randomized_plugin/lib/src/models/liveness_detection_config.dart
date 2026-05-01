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
  }) : assert(
         !useCustomizedLabel || customizedLabel != null,
         'customizedLabel must not be null when useCustomizedLabel is true',
       );
}
