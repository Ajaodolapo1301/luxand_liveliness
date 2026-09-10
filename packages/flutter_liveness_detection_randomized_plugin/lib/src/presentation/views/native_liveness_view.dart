import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/native_capture_service.dart';
import '../../models/liveness_detection_config.dart';
import '../widgets/liveness_detection_step_overlay_widget.dart';
import '../../core/constants/liveness_oval_constants.dart';
import 'native_capture_view.dart';

/// Native-camera liveness flow (Android). Renders the SAME oval overlay UI as
/// [LivenessDetectionView] on top of the native [NativeCameraPreview], but the
/// camera and MediaPipe face detection run natively — Dart only receives the
/// face box and runs the in-oval + stability + countdown gating.
///
/// Scope: delayed face capture + manual snap (no challenges). Pops the captured
/// JPEG path, or null on cancel/timeout.
class NativeLivenessView extends StatefulWidget {
  final LivenessDetectionConfig config;

  const NativeLivenessView({super.key, required this.config});

  @override
  State<NativeLivenessView> createState() => _NativeLivenessViewState();
}

class _NativeLivenessViewState extends State<NativeLivenessView> {
  final _controller = NativeCaptureController();
  StreamSubscription<NativeFaceDetection>? _sub;
  NativePreview? _preview;
  String? _error;

  Size? _screenSize;
  bool _faceDetectedState = false;
  bool _isTakingPicture = false;

  int _delayedStableConsecutiveFrames = 0;
  int _outOfOvalConsecutiveFrames = 0;
  Timer? _delayedFaceCaptureTimer;
  int? _delayedFaceCaptureSecondsRemaining;
  Timer? _timeoutTimer;

  LivenessDetectionConfig get _config => widget.config;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final preview = await _controller.initialize(
        faceDetectionMaxDim: _config.faceDetectionMaxDim,
        fastMode: _config.faceDetectionFastMode,
      );
      // dispose() may have run while that await was pending. Checking here
      // rather than after the wiring below matters: dispose() cancels _sub and
      // _timeoutTimer, so anything created past this point would never be
      // cancelled and would keep driving a dead State.
      if (!mounted) return;
      _sub = _controller.detections().listen(_onDetection);
      _timeoutTimer = Timer(
        Duration(seconds: _config.durationLivenessVerify ?? 45),
        () => _complete(null),
      );
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _delayedFaceCaptureTimer?.cancel();
    _timeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Mirrors LivenessDetectionView._isFaceInOval so behavior matches the old
  /// flow. The native box is already upright and non-mirrored.
  bool _isFaceInOval(NativeFaceDetection face) {
    final screenSize = _screenSize;
    if (screenSize == null) return true;
    if (face.imageWidth == 0 || face.imageHeight == 0) return false;

    const double ovalW = LivenessOvalConstants.width;
    const double ovalH = LivenessOvalConstants.height;
    const double verticalOffset = LivenessOvalConstants.verticalOffset;

    double normX = face.centerX / face.imageWidth;
    double normY = face.centerY / face.imageHeight;
    if (face.mirror) normX = 1.0 - normX;

    const ovalCx = 0.5;
    final ovalCy = (screenSize.height / 2 + verticalOffset) / screenSize.height;
    final ovalA = (ovalW / 2) / screenSize.width;
    final ovalB = (ovalH / 2) / screenSize.height;

    const double tolerance = LivenessOvalConstants.inOvalTolerance;
    final dx = (normX - ovalCx) / (ovalA * tolerance);
    final dy = (normY - ovalCy) / (ovalB * tolerance);
    return dx * dx + dy * dy <= 1.0;
  }

  void _onDetection(NativeFaceDetection face) {
    if (!mounted) return;
    if (_isTakingPicture) return;

    final rawInOval = face.hasFace && _isFaceInOval(face);

    if (rawInOval) {
      _outOfOvalConsecutiveFrames = 0;
    } else {
      _outOfOvalConsecutiveFrames++;
    }

    final debounceLimit = _config.faceOutOfOvalDebounceFrames;
    final faceInOval = rawInOval ||
        (_faceDetectedState && _outOfOvalConsecutiveFrames < debounceLimit);

    if (!faceInOval) {
      _delayedStableConsecutiveFrames = 0;
      _cancelDelayedFaceCapture();
      if (mounted && _faceDetectedState) {
        setState(() => _faceDetectedState = false);
      }
      return;
    }

    if (mounted && !_faceDetectedState) {
      setState(() => _faceDetectedState = true);
    }

    // Grace period: keep UI/countdown but don't advance until raw in-oval.
    if (!rawInOval) return;

    if (_config.enableDelayedFaceCapture) {
      if (_delayedFaceCaptureTimer?.isActive ?? false) {
        return; // countdown already running
      }
      _delayedStableConsecutiveFrames++;
      if (_delayedStableConsecutiveFrames >=
          _config.delayedFaceCaptureStableFrames) {
        _delayedStableConsecutiveFrames = 0;
        _startDelayedFaceCountdown();
      }
    }
  }

  void _cancelDelayedFaceCapture() {
    _delayedFaceCaptureTimer?.cancel();
    _delayedFaceCaptureTimer = null;
    if (mounted && _delayedFaceCaptureSecondsRemaining != null) {
      setState(() => _delayedFaceCaptureSecondsRemaining = null);
    }
  }

  void _startDelayedFaceCountdown() {
    _delayedFaceCaptureTimer?.cancel();
    if (!mounted) return;
    final secs = _config.delayedFaceCaptureAfterSeconds;
    if (secs <= 0) {
      if (_faceDetectedState) _takePicture();
      return;
    }
    var remaining = secs;
    setState(() => _delayedFaceCaptureSecondsRemaining = remaining);
    _delayedFaceCaptureTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      remaining--;
      if (remaining <= 0) {
        t.cancel();
        _delayedFaceCaptureTimer = null;
        setState(() => _delayedFaceCaptureSecondsRemaining = null);
        if (_faceDetectedState) _takePicture();
      } else {
        setState(() => _delayedFaceCaptureSecondsRemaining = remaining);
      }
    });
  }

  String _emptyStepsInstruction() {
    final base = _config.delayedFaceCaptureInstruction;
    if (_config.showAnimatedCaptureCountdown) return base;
    final r = _delayedFaceCaptureSecondsRemaining;
    if (r == null) return base;
    return '$base\nPhoto in ${r}s';
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture || !mounted) return;
    _cancelDelayedFaceCapture();
    setState(() => _isTakingPicture = true);
    try {
      final path = await _controller.capture();
      _complete(path);
    } catch (_) {
      if (mounted) setState(() => _isTakingPicture = false);
    }
  }

  void _complete(String? path) {
    if (!mounted) return;
    _sub?.cancel();
    _timeoutTimer?.cancel();
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;
    final preview = _preview;

    return Scaffold(
      backgroundColor: _config.theme?.backgroundColor ??
          (_config.isDarkMode ? Colors.black : Colors.white),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera failed:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : preview == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : LivenessDetectionStepOverlayWidget(
                  cameraController: null,
                  camera: NativeCameraPreview(preview: preview),
                  duration: _config.durationLivenessVerify,
                  showDurationUiText: _config.showDurationUiText,
                  isDarkMode: _config.isDarkMode,
                  isFaceDetected: _faceDetectedState,
                  steps: const [],
                  showCurrentStep: _config.showCurrentStep,
                  theme: _config.theme,
                  onCompleted: _takePicture,
                  onManualSnap: _takePicture,
                  enableManualSnapFallback: _config.enableManualSnapFallback,
                  manualSnapAfterSeconds: _config.manualSnapAfterSeconds,
                  manualSnapLabel: _config.manualSnapLabel,
                  manualSnapRequireFaceDetected:
                      _config.manualSnapRequireFaceDetected,
                  emptyStepsInstruction: _emptyStepsInstruction(),
                  captureCountdownSeconds: _config.enableDelayedFaceCapture &&
                          _config.showAnimatedCaptureCountdown
                      ? _delayedFaceCaptureSecondsRemaining
                      : null,
                ),
    );
  }
}
