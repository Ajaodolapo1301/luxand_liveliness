// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_liveness_detection_randomized_plugin/index.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/core/constants/liveness_detection_step_constant.dart';
import 'package:face_detection_tflite/face_detection_tflite.dart' as mp;
import 'package:flutter_liveness_detection_randomized_plugin/src/core/constants/liveness_oval_constants.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/core/utils/liveness_face_detection_logger.dart';
import 'package:collection/collection.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

List<CameraDescription> availableCams = [];

class LivenessDetectionView extends StatefulWidget {
  final LivenessDetectionConfig config;

  const LivenessDetectionView({
    super.key,
    required this.config,
  });

  @override
  State<LivenessDetectionView> createState() => _LivenessDetectionScreenState();
}

class _LivenessDetectionScreenState extends State<LivenessDetectionView> {
  // Camera related variables
  CameraController? _cameraController;
  int _cameraIndex = 0;
  bool _isBusy = false;
  bool _isTakingPicture = false;
  late final LivenessFaceDetectionLogger _faceLogger;
  Timer? _timerToDetectFace;

  // Detection state variables
  late bool _isInfoStepCompleted;
  bool _isProcessingStep = false;
  bool _faceDetectedState = false;
  Size? _screenSize;
  List<LivenessDetectionStepItem> _shuffledSteps = [];

  int _delayedStableConsecutiveFrames = 0;
  int _outOfOvalConsecutiveFrames = 0;
  Timer? _delayedFaceCaptureTimer;
  int? _delayedFaceCaptureSecondsRemaining;

  // Brightness Screen
  Future<void> setApplicationBrightness(double brightness) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(
        brightness,
      );
    } catch (e) {
      throw 'Failed to set application brightness';
    }
  }

  Future<void> resetApplicationBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      throw 'Failed to reset application brightness';
    }
  }

  // Steps related variables
  late final List<LivenessDetectionStepItem> steps;
  final GlobalKey<LivenessDetectionStepOverlayWidgetState> _stepsKey =
      GlobalKey<LivenessDetectionStepOverlayWidgetState>();

  static void shuffleListLivenessChallenge({
    required List<LivenessDetectionStepItem> list,
    required bool isSmileLast,
  }) {
    if (isSmileLast) {
      int? smileIndex = list.indexWhere(
        (item) => item.step == LivenessDetectionStep.smile,
      );

      if (smileIndex != -1) {
        LivenessDetectionStepItem smileItem = list.removeAt(smileIndex);
        list.shuffle(Random());
        list.add(smileItem);
      } else {
        list.shuffle(Random());
      }
    } else {
      list.shuffle(Random());
    }
  }

  Future<XFile?> _compressImage(XFile originalFile) async {
    final int quality = widget.config.imageQuality;

    if (quality >= 100) {
      return originalFile;
    }

    try {
      final bytes = await originalFile.readAsBytes();

      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        return originalFile;
      }

      final tempDir = await getTemporaryDirectory();
      final String targetPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressedBytes = img.encodeJpg(originalImage, quality: quality);

      final File compressedFile = await File(
        targetPath,
      ).writeAsBytes(compressedBytes);

      return XFile(compressedFile.path);
    } catch (e) {
      debugPrint("Error compressing image: $e");
      return originalFile;
    }
  }

  List<T> manualRandomItemLiveness<T>(List<T> list) {
    final random = Random();
    List<T> shuffledList = List.from(list);
    for (int i = shuffledList.length - 1; i > 0; i--) {
      int j = random.nextInt(i + 1);

      T temp = shuffledList[i];
      shuffledList[i] = shuffledList[j];
      shuffledList[j] = temp;
    }
    return shuffledList;
  }

  List<LivenessDetectionStepItem> customizedLivenessLabel(
    LivenessDetectionLabelModel label,
  ) {
    List<LivenessDetectionStepItem> customizedSteps = [];

    // Add blink step if not explicitly skipped (empty string skips)
    if (label.blink != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.blink,
          title: label.blink ?? "Blink 2-3 Times",
        ),
      );
    }

    // Add lookRight step if not explicitly skipped
    if (label.lookRight != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.lookRight,
          title: label.lookRight ?? "Look RIGHT",
        ),
      );
    }

    // Add lookLeft step if not explicitly skipped
    if (label.lookLeft != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.lookLeft,
          title: label.lookLeft ?? "Look LEFT",
        ),
      );
    }

    // Add lookUp step if not explicitly skipped
    if (label.lookUp != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.lookUp,
          title: label.lookUp ?? "Look UP",
        ),
      );
    }

    // Add lookDown step if not explicitly skipped
    if (label.lookDown != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.lookDown,
          title: label.lookDown ?? "Look DOWN",
        ),
      );
    }

    // Add smile step if not explicitly skipped
    if (label.smile != "") {
      customizedSteps.add(
        LivenessDetectionStepItem(
          step: LivenessDetectionStep.smile,
          title: label.smile ?? "Smile",
        ),
      );
    }

    return customizedSteps;
  }

  @override
  void initState() {
    _faceLogger = LivenessFaceDetectionLogger(
      enabled: widget.config.enableFaceDetectionLogging,
    );
    _preInitCallBack();
    super.initState();
    if (widget.config.enableCooldownOnFailure) {
      LivenessCooldownService.instance.configure(
        maxFailedAttempts: widget.config.maxFailedAttempts,
        cooldownMinutes: widget.config.cooldownMinutes,
      );
      LivenessCooldownService.instance.initializeCooldownTimer();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _postFrameCallBack());
  }

  @override
  void dispose() {
    _timerToDetectFace?.cancel();
    _timerToDetectFace = null;
    _delayedFaceCaptureTimer?.cancel();
    _delayedFaceCaptureTimer = null;
    _cameraController?.dispose();
    MediaPipeFaceDetectorHelper.instance.dispose();

    if (widget.config.isEnableMaxBrightness) {
      resetApplicationBrightness();
    }
    super.dispose();
  }

  void _preInitCallBack() {
    _isInfoStepCompleted = !widget.config.startWithInfoScreen;
    
    // Initialize and shuffle steps fresh each time
    _initializeShuffledSteps();
    
    if (widget.config.isEnableMaxBrightness) {
      setApplicationBrightness(1.0);
    }
  }

  void _postFrameCallBack() async {
    availableCams = await availableCameras();
    if (availableCams.any(
      (element) =>
          element.lensDirection == CameraLensDirection.front &&
          element.sensorOrientation == 90,
    )) {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere(
          (element) =>
              element.lensDirection == CameraLensDirection.front &&
              element.sensorOrientation == 90,
        ),
      );
    } else {
      _cameraIndex = availableCams.indexOf(
        availableCams.firstWhere(
          (element) => element.lensDirection == CameraLensDirection.front,
        ),
      );
    }
    if (!widget.config.startWithInfoScreen) {
      _startLiveFeed();
    }

    // Steps are shuffled fresh in _preInitCallBack
  }

  void _startLiveFeed() async {
    final camera = availableCams[_cameraIndex];
    MediaPipeFaceDetectorHelper.instance.logEnabled =
        widget.config.enableFaceDetectionLogging;
    _faceLogger.info(
      'Starting camera stream | lens=${camera.lensDirection.name} '
      'sensorOrientation=${camera.sensorOrientation} '
      'resolution=${widget.config.cameraResolution.name} '
      'maxDim=${widget.config.faceDetectionMaxDim} '
      'mode=${widget.config.faceDetectionFastMode ? "fast" : "standard"}',
    );
    _cameraController = CameraController(
      camera,
      widget.config.cameraResolution,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : ImageFormatGroup.bgra8888,
    );

    _cameraController?.initialize().then((_) async {
      if (!mounted) return;
      try {
        await MediaPipeFaceDetectorHelper.instance.ensureInitialized();
      } catch (e) {
        _faceLogger.error('FaceDetector init failed — detection will not run', e);
        return;
      }
      if (!mounted) return;
      _faceLogger.info('Camera initialized — image stream starting');
      _cameraController?.startImageStream(_processCameraImage);
      setState(() {});
    });
    _startFaceDetectionTimer();
  }

  void _startFaceDetectionTimer() {
    _timerToDetectFace = Timer(
      Duration(seconds: widget.config.durationLivenessVerify ?? 45),
      () => _onDetectionCompleted(imgPath: null),
    );
  }

  void _cancelDelayedFaceCapture() {
    _delayedFaceCaptureTimer?.cancel();
    _delayedFaceCaptureTimer = null;
    if (!mounted) return;
    if (_delayedFaceCaptureSecondsRemaining != null) {
      setState(() => _delayedFaceCaptureSecondsRemaining = null);
    }
  }

  void _startDelayedFaceCountdown() {
    _delayedFaceCaptureTimer?.cancel();
    final secs = widget.config.delayedFaceCaptureAfterSeconds;
    if (secs <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _faceDetectedState) _takePicture();
      });
      return;
    }
    var remaining = secs;
    if (!mounted) return;
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
        if (_faceDetectedState) {
          _takePicture();
        }
      } else {
        setState(() => _delayedFaceCaptureSecondsRemaining = remaining);
      }
    });
  }

  String _delayedFaceEmptyInstruction() {
    final base = widget.config.delayedFaceCaptureInstruction;
    if (widget.config.showAnimatedCaptureCountdown) return base;
    final r = _delayedFaceCaptureSecondsRemaining;
    if (r == null) return base;
    return '$base\nPhoto in ${r}s';
  }

  DeviceOrientation _effectiveDeviceOrientation() {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      return controller.value.deviceOrientation;
    }
    if (!mounted) return DeviceOrientation.portraitUp;
    return MediaQuery.orientationOf(context) == Orientation.portrait
        ? DeviceOrientation.portraitUp
        : DeviceOrientation.landscapeLeft;
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isBusy) return;
    if (_isTakingPicture) return;
    _isBusy = true;

    try {
      final camera = availableCams[_cameraIndex];
      final mode = widget.config.faceDetectionFastMode
          ? mp.FaceDetectionMode.fast
          : mp.FaceDetectionMode.standard;
      final maxDim = widget.config.faceDetectionMaxDim;
      final deviceOrientation = _effectiveDeviceOrientation();
      final isFrontCamera =
          camera.lensDirection == CameraLensDirection.front;
      final rotation = mp.rotationForFrame(
        width: cameraImage.width,
        height: cameraImage.height,
        sensorOrientation: camera.sensorOrientation,
        isFrontCamera: isFrontCamera,
        deviceOrientation: deviceOrientation,
      );
      final detectionImageSize = mp.detectionSize(
        width: cameraImage.width,
        height: cameraImage.height,
        rotation: rotation,
        maxDim: maxDim,
      );
      final mirrorHorizontally = Platform.isAndroid && isFrontCamera;

      final faces = await MediaPipeFaceDetectorHelper.instance.processCameraImage(
        cameraImage,
        camera: camera,
        deviceOrientation: deviceOrientation,
        rotation: rotation,
        mode: mode,
        maxDim: maxDim,
      );

      await _processDetectedFaces(
        faces,
        detectionImageSize,
        mirrorHorizontally: mirrorHorizontally,
      );
    } finally {
      _isBusy = false;
      if (mounted) setState(() {});
    }
  }

  /// Returns true if the face center falls inside (or close to) the oval region.
  /// [detectionImageSize] must match [mp.detectionSize] (upright, downscaled space).
  bool _isFaceInOval(
    DetectedFace face,
    Size detectionImageSize, {
    required bool mirrorHorizontally,
  }) {
    final screenSize = _screenSize;
    if (screenSize == null) return true; // fallback before first build

    const double ovalW = LivenessOvalConstants.width;
    const double ovalH = LivenessOvalConstants.height;
    const double verticalOffset = LivenessOvalConstants.verticalOffset;

    final fc = face.boundingBox.center;
    double normX = fc.dx / detectionImageSize.width;
    double normY = fc.dy / detectionImageSize.height;
    if (mirrorHorizontally) {
      normX = 1.0 - normX;
    }

    const ovalCx = 0.5;
    final ovalCy = (screenSize.height / 2 + verticalOffset) / screenSize.height;
    final ovalA = (ovalW / 2) / screenSize.width;
    final ovalB = (ovalH / 2) / screenSize.height;

    const double tolerance = LivenessOvalConstants.inOvalTolerance;
    final dx = (normX - ovalCx) / (ovalA * tolerance);
    final dy = (normY - ovalCy) / (ovalB * tolerance);
    return dx * dx + dy * dy <= 1.0;
  }

  Future<void> _processDetectedFaces(
    List<DetectedFace> faces,
    Size detectionImageSize, {
    required bool mirrorHorizontally,
  }) async {
    final rawInOval = faces.isNotEmpty &&
        _isFaceInOval(
          faces.first,
          detectionImageSize,
          mirrorHorizontally: mirrorHorizontally,
        );

    if (rawInOval) {
      _outOfOvalConsecutiveFrames = 0;
    } else {
      _outOfOvalConsecutiveFrames++;
    }

    final debounceLimit = widget.config.faceOutOfOvalDebounceFrames;
    final faceInOval = rawInOval ||
        (_faceDetectedState && _outOfOvalConsecutiveFrames < debounceLimit);

    final face = faces.isNotEmpty ? faces.first : null;
    _faceLogger.logDetectionFrame(
      faceCount: faces.length,
      faceInOval: faceInOval,
      intervalFrames: widget.config.faceDetectionLogIntervalFrames,
      bbox: face == null
          ? null
          : 'bbox=${face.boundingBox.left.toStringAsFixed(0)},'
              '${face.boundingBox.top.toStringAsFixed(0)},'
              '${face.boundingBox.width.toStringAsFixed(0)}x'
              '${face.boundingBox.height.toStringAsFixed(0)}',
      metrics: face == null
          ? null
          : 'leftEye=${_fmtProb(face.leftEyeOpenProbability)} '
              'rightEye=${_fmtProb(face.rightEyeOpenProbability)} '
              'smile=${_fmtProb(face.smilingProbability)}',
      extras: 'detSize=${detectionImageSize.width.toStringAsFixed(0)}x'
          '${detectionImageSize.height.toStringAsFixed(0)} '
          'mirror=$mirrorHorizontally '
          'rawInOval=$rawInOval outStreak=$_outOfOvalConsecutiveFrames',
    );

    if (!faceInOval) {
      _delayedStableConsecutiveFrames = 0;
      _cancelDelayedFaceCapture();
      _resetSteps();
      if (mounted) setState(() => _faceDetectedState = false);
    } else {
      if (mounted) setState(() => _faceDetectedState = true);

      // Grace period: keep UI/countdown, but don't advance until raw in-oval again.
      if (!rawInOval) return;

      if (widget.config.enableDelayedFaceCapture) {
        if (_delayedFaceCaptureTimer?.isActive ?? false) {
          // Countdown already running; keep holding position.
        } else {
          _delayedStableConsecutiveFrames++;
          final need = widget.config.delayedFaceCaptureStableFrames;
          if (_delayedStableConsecutiveFrames >= need) {
            _delayedStableConsecutiveFrames = 0;
            _startDelayedFaceCountdown();
          }
        }
      } else {
        final currentIndex = _stepsKey.currentState?.currentIndex ?? 0;
        final currentSteps = _getStepsToUse();
        if (currentIndex < currentSteps.length) {
          _detectFace(
            face: faces.first,
            step: currentSteps[currentIndex].step,
          );
        }
      }
    }
  }

  String _fmtProb(double? value) =>
      value == null ? 'n/a' : value.toStringAsFixed(2);

  void _detectFace({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    if (_isProcessingStep) return;

    _faceLogger.info('Challenge step=$step');

    switch (step) {
      case LivenessDetectionStep.blink:
        await _handlingBlinkStep(face: face, step: step);
        break;

      case LivenessDetectionStep.lookRight:
        await _handlingTurnRight(face: face, step: step);
        break;

      case LivenessDetectionStep.lookLeft:
        await _handlingTurnLeft(face: face, step: step);
        break;

      case LivenessDetectionStep.lookUp:
        await _handlingLookUp(face: face, step: step);
        break;

      case LivenessDetectionStep.lookDown:
        await _handlingLookDown(face: face, step: step);
        break;

      case LivenessDetectionStep.smile:
        await _handlingSmile(face: face, step: step);
        break;
    }
  }

  Future<void> _completeStep({required LivenessDetectionStep step}) async {
    if (mounted) setState(() {});
    await _stepsKey.currentState?.nextPage();
    _stopProcessing();
  }

  void _takePicture() async {
    try {
      if (_cameraController == null || _isTakingPicture) return;

      _cancelDelayedFaceCapture();

      if (mounted) setState(() => _isTakingPicture = true);
      await _cameraController?.stopImageStream();

      final XFile? clickedImage = await _cameraController?.takePicture();
      if (clickedImage == null) {
        _startLiveFeed();
        if (mounted) setState(() => _isTakingPicture = false);
        return;
      }

      final XFile? finalImage = await _compressImage(clickedImage);

      if (mounted) setState(() => _isTakingPicture = false);
      _onDetectionCompleted(imgPath: finalImage?.path);
    } catch (e) {
      if (mounted) setState(() => _isTakingPicture = false);
      _startLiveFeed();
    }
  }

  void _onDetectionCompleted({String? imgPath}) async {
    _faceLogger.info(
      imgPath == null
          ? 'Liveness timed out (limit ${widget.config.durationLivenessVerify ?? 45}s)'
          : 'Liveness capture success | path=$imgPath',
    );
    if (widget.config.isEnableSnackBar) {
      final snackBar = SnackBar(
        content: Text(
          imgPath == null
              ? 'Verification of liveness detection failed, please try again. (Exceeds time limit ${widget.config.durationLivenessVerify ?? 45} second.)'
              : 'Verification of liveness detection success!',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
    if (!mounted) return;
    Navigator.of(context).pop(imgPath);
  }

  void _resetSteps() {
    List<LivenessDetectionStepItem> currentSteps = _getStepsToUse();
    
    for (var step in currentSteps) {
      final index = currentSteps.indexWhere((p1) => p1.step == step.step);
      if (index != -1) {
        currentSteps[index] = currentSteps[index].copyWith();
      }
    }
    
    if (_stepsKey.currentState?.currentIndex != 0) {
      _stepsKey.currentState?.reset();
    }
    
    if (mounted) setState(() {});
  }

  void _startProcessing() {
    if (!mounted) return;
    if (mounted) setState(() => _isProcessingStep = true);
  }

  void _stopProcessing() {
    if (!mounted) return;
    if (mounted) setState(() => _isProcessingStep = false);
  }

  /// Initialize and shuffle steps fresh each time
  void _initializeShuffledSteps() {
    if (widget.config.enableDelayedFaceCapture) {
      _shuffledSteps = [];
      return;
    }

    List<LivenessDetectionStepItem> baseSteps;
    
    if (widget.config.useCustomizedLabel && widget.config.customizedLabel != null) {
      baseSteps = customizedLivenessLabel(widget.config.customizedLabel!);
    } else {
      baseSteps = List.from(stepLiveness); // Create a copy to avoid modifying the original
    }
    
    shuffleListLivenessChallenge(
      list: baseSteps,
      isSmileLast: widget.config.useCustomizedLabel
          ? false
          : widget.config.shuffleListWithSmileLast,
    );
    
    _shuffledSteps = baseSteps;
  }

  /// Helper method to get the shuffled steps list
  List<LivenessDetectionStepItem> _getStepsToUse() {
    return _shuffledSteps;
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: widget.config.theme?.backgroundColor ?? (widget.config.isDarkMode ? Colors.black : Colors.white),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        _isInfoStepCompleted
            ? _buildDetectionBody()
            : LivenessDetectionTutorialScreen(
                duration: widget.config.durationLivenessVerify ?? 45,
                isDarkMode: widget.config.isDarkMode,
                onStartTap: () {
                  if (mounted) setState(() => _isInfoStepCompleted = true);
                  _startLiveFeed();
                },
              ),
      ],
    );
  }

  Widget _buildDetectionBody() {
    if (_cameraController == null ||
        _cameraController?.value.isInitialized == false) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Stack(
      children: [
        Container(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          color: Colors.black,
        ),
        LivenessDetectionStepOverlayWidget(
          cameraController: _cameraController,
          duration: widget.config.durationLivenessVerify,
          showDurationUiText: widget.config.showDurationUiText,
          isDarkMode: widget.config.isDarkMode,
          isFaceDetected: _faceDetectedState,
          camera: CameraPreview(_cameraController!),
          key: _stepsKey,
          steps: _getStepsToUse(),
          showCurrentStep: widget.config.showCurrentStep,
          theme: widget.config.theme,
          onCompleted: _takePicture,
          onManualSnap: _takePicture,
          enableManualSnapFallback: widget.config.enableManualSnapFallback &&
              !widget.config.enableDelayedFaceCapture,
          manualSnapAfterSeconds: widget.config.manualSnapAfterSeconds,
          manualSnapLabel: widget.config.manualSnapLabel,
          manualSnapRequireFaceDetected:
              widget.config.manualSnapRequireFaceDetected,
          emptyStepsInstruction: widget.config.enableDelayedFaceCapture
              ? _delayedFaceEmptyInstruction()
              : '',
          captureCountdownSeconds:
              widget.config.enableDelayedFaceCapture &&
                  widget.config.showAnimatedCaptureCountdown
              ? _delayedFaceCaptureSecondsRemaining
              : null,
        ),
      ],
    );
  }

  Future<void> _handlingBlinkStep({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    final blinkThreshold =
        FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                .firstWhereOrNull((p0) => p0 is LivenessThresholdBlink)
            as LivenessThresholdBlink?;

    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;
    if (leftEye == null || rightEye == null) {
      _faceLogger.info(
        'Blink waiting for mesh | leftEye=$leftEye rightEye=$rightEye',
      );
      return;
    }

    _faceLogger.logDetectionFrame(
      faceCount: 1,
      faceInOval: true,
      intervalFrames: widget.config.faceDetectionLogIntervalFrames,
      metrics: 'blink leftEye=${leftEye.toStringAsFixed(2)} '
          'rightEye=${rightEye.toStringAsFixed(2)} '
          'threshold=${blinkThreshold?.leftEyeProbability ?? 0.25}',
    );

    if (leftEye < (blinkThreshold?.leftEyeProbability ?? 0.25) &&
        rightEye < (blinkThreshold?.rightEyeProbability ?? 0.25)) {
      _faceLogger.info('Blink passed');
      _startProcessing();
      await _completeStep(step: step);
    }
  }

  Future<void> _handlingTurnRight({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    if (Platform.isAndroid) {
      final headTurnThreshold =
          FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                  .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
              as LivenessThresholdHead?;
      if ((face.headEulerAngleY ?? 0) <
          (headTurnThreshold?.rotationAngle ?? -30)) {
        _startProcessing();
        await _completeStep(step: step);
      }
    } else if (Platform.isIOS) {
      final headTurnThreshold =
          FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                  .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
              as LivenessThresholdHead?;
      if ((face.headEulerAngleY ?? 0) >
          (headTurnThreshold?.rotationAngle ?? 30)) {
        _startProcessing();
        await _completeStep(step: step);
      }
    }
  }

  Future<void> _handlingTurnLeft({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    if (Platform.isAndroid) {
      final headTurnThreshold =
          FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                  .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
              as LivenessThresholdHead?;
      if ((face.headEulerAngleY ?? 0) >
          (headTurnThreshold?.rotationAngle ?? 30)) {
        _startProcessing();
        await _completeStep(step: step);
      }
    } else if (Platform.isIOS) {
      final headTurnThreshold =
          FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                  .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
              as LivenessThresholdHead?;
      if ((face.headEulerAngleY ?? 0) <
          (headTurnThreshold?.rotationAngle ?? -30)) {
        _startProcessing();
        await _completeStep(step: step);
      }
    }
  }

  Future<void> _handlingLookUp({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    final headTurnThreshold =
        FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
            as LivenessThresholdHead?;
    if ((face.headEulerAngleX ?? 0) >
        (headTurnThreshold?.rotationAngle ?? 20)) {
      _startProcessing();
      await _completeStep(step: step);
    }
  }

  Future<void> _handlingLookDown({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    final headTurnThreshold =
        FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                .firstWhereOrNull((p0) => p0 is LivenessThresholdHead)
            as LivenessThresholdHead?;
    if ((face.headEulerAngleX ?? 0) <
        (headTurnThreshold?.rotationAngle ?? -15)) {
      _startProcessing();
      await _completeStep(step: step);
    }
  }

  Future<void> _handlingSmile({
    required DetectedFace face,
    required LivenessDetectionStep step,
  }) async {
    final smileThreshold =
        FlutterLivenessDetectionRandomizedPlugin.instance.thresholdConfig
                .firstWhereOrNull((p0) => p0 is LivenessThresholdSmile)
            as LivenessThresholdSmile?;

    final smile = face.smilingProbability;
    if (smile == null) {
      _faceLogger.info('Smile waiting for mesh | smile=$smile');
      return;
    }

    _faceLogger.logDetectionFrame(
      faceCount: 1,
      faceInOval: true,
      intervalFrames: widget.config.faceDetectionLogIntervalFrames,
      metrics: 'smile=${smile.toStringAsFixed(2)} '
          'threshold=${smileThreshold?.probability ?? 0.65}',
    );

    if (smile > (smileThreshold?.probability ?? 0.65)) {
      _faceLogger.info('Smile passed');
      _startProcessing();
      await _completeStep(step: step);
    }
  }
}
