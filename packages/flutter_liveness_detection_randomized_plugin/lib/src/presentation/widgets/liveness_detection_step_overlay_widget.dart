import 'package:flutter/cupertino.dart';
import 'package:flutter_liveness_detection_randomized_plugin/index.dart';
import 'package:flutter_liveness_detection_randomized_plugin/src/presentation/widgets/circular_progress_widget/circular_progress_painter.dart';

class LivenessDetectionStepOverlayWidget extends StatefulWidget {
  final List<LivenessDetectionStepItem> steps;
  final VoidCallback onCompleted;
  final Widget camera;
  final CameraController? cameraController;
  final bool isFaceDetected;
  final bool showCurrentStep;
  final bool isDarkMode;
  final bool showDurationUiText;
  final int? duration;
  final LivenessDetectionTheme? theme;

  const LivenessDetectionStepOverlayWidget({
    super.key,
    required this.steps,
    required this.onCompleted,
    required this.camera,
    required this.cameraController,
    required this.isFaceDetected,
    this.showCurrentStep = false,
    this.isDarkMode = true,
    this.showDurationUiText = false,
    this.duration,
    this.theme,
  });

  @override
  State<LivenessDetectionStepOverlayWidget> createState() =>
      LivenessDetectionStepOverlayWidgetState();
}

class LivenessDetectionStepOverlayWidgetState
    extends State<LivenessDetectionStepOverlayWidget> {
  int get currentIndex => _currentIndex;

  bool _isLoading = false;
  int _currentIndex = 0;
  double _currentStepIndicator = 0; // 0 – 100

  late final PageController _pageController;
  bool _pageViewVisible = false;
  Timer? _countdownTimer;
  int _remainingDuration = 0;

  // Oval dimensions
  static const double _ovalW = 280;
  static const double _ovalH = 370;
  static const double _verticalOffset = -40.0;

  // Theme helpers
  Color get _overlayColor => const Color(0xCC000000);
  Color get _ringProgressColor =>
      widget.theme?.ringProgressColor ?? Colors.green;
  Color get _ringTrackColor =>
      widget.theme?.ringTrackColor ?? const Color(0x55FFFFFF);
  Color get _instructionCardColor =>
      widget.theme?.instructionCardColor ?? const Color(0xFF1A1A2E);
  Color get _instructionTextColor =>
      widget.theme?.instructionTextColor ?? Colors.white;
  double get _instructionFontSize => widget.theme?.instructionFontSize ?? 20;
  Color get _statusTextColor =>
      widget.theme?.statusTextColor ?? Colors.white70;
  String get _faceFoundLabel =>
      widget.theme?.faceFoundLabel ?? 'Face detected';
  String get _faceNotFoundLabel =>
      widget.theme?.faceNotFoundLabel ?? 'Position your face in the frame';
  String get _backLabel => widget.theme?.backLabel ?? 'Cancel';

  double _getStepIncrement(int stepLength) => 100 / stepLength;
  String get stepCounter => '$_currentIndex/${widget.steps.length}';

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.duration != null && widget.showDurationUiText) {
      _remainingDuration = widget.duration!;
      _startCountdownTimer();
    }
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _pageViewVisible = true));
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingDuration > 0) {
        setState(() => _remainingDuration--);
      } else {
        _countdownTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> nextPage() async {
    if (_isLoading) return;
    if (_currentIndex + 1 <= widget.steps.length - 1) {
      await _handleNextStep();
    } else {
      await _handleCompletion();
    }
  }

  Future<void> _handleNextStep() async {
    _showLoader();
    await Future.delayed(const Duration(milliseconds: 100));
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 1),
      curve: Curves.easeIn,
    );
    await Future.delayed(const Duration(seconds: 1));
    _hideLoader();
    _updateState();
  }

  Future<void> _handleCompletion() async {
    _showLoader();
    _updateState();
    widget.onCompleted();
  }

  void _updateState() {
    if (mounted) {
      setState(() {
        _currentIndex++;
        _currentStepIndicator += _getStepIncrement(widget.steps.length);
      });
    }
  }

  void reset() {
    _pageController.jumpToPage(0);
    if (mounted) {
      setState(() {
        _currentIndex = 0;
        _currentStepIndicator = 0;
      });
    }
  }

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  String _getRemainingTimeText(int duration) {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      children: [
        // Full-screen camera
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: widget.cameraController?.value.previewSize?.height ?? screenSize.width,
              height: widget.cameraController?.value.previewSize?.width ?? screenSize.height,
              child: widget.camera,
            ),
          ),
        ),

        // Dark overlay + oval cutout + dotted progress ring
        SizedBox.expand(
          child: CustomPaint(
            painter: SmileIdOverlayPainter(
              overlayColor: _overlayColor,
              ringTrackColor: _ringTrackColor,
              ringProgressColor: _ringProgressColor,
              progress: _currentStepIndicator / 100,
              ovalWidth: _ovalW,
              ovalHeight: _ovalH,
              ringThickness: 4,
              verticalOffset: _verticalOffset,
            ),
          ),
        ),

        // Top bar: back + timer + step counter
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(_backLabel,
                      style: TextStyle(color: _statusTextColor, fontSize: 15)),
                ),
                if (widget.showDurationUiText)
                  Text(
                    _getRemainingTimeText(_remainingDuration),
                    style: TextStyle(
                        color: _statusTextColor, fontWeight: FontWeight.bold),
                  ),
                if (widget.showCurrentStep)
                  Text(stepCounter,
                      style: TextStyle(color: _statusTextColor, fontSize: 15)),
              ],
            ),
          ),
        ),

        // Face status label just below the oval
        Positioned(
          left: 0,
          right: 0,
          top: screenSize.height / 2 + _ovalH / 2 + _verticalOffset + 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isFaceDetected
                      ? _ringProgressColor
                      : Colors.white38,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.isFaceDetected ? _faceFoundLabel : _faceNotFoundLabel,
                style: TextStyle(color: _statusTextColor, fontSize: 13),
              ),
            ],
          ),
        ),

        // Bottom instruction card
        Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pageViewVisible)
                AbsorbPointer(
                  absorbing: true,
                  child: SizedBox(
                    height: 80,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.steps.length,
                      itemBuilder: (_, index) => Container(
                        decoration: BoxDecoration(
                          color: _instructionCardColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Text(
                          widget.steps[index].title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _instructionTextColor,
                            fontSize: _instructionFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              CupertinoActivityIndicator(
                color: _isLoading ? _instructionTextColor : Colors.transparent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
