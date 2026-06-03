import 'package:flutter_liveness_detection_randomized_plugin/index.dart';

/// Harness to validate the native Texture preview AND native MediaPipe face
/// detection on a real device.
///
/// Shows the live native camera with a green box drawn over the detected face.
/// Check: box tracks the face, sits tight around it, and does not lag badly.
/// No oval/countdown/capture yet — that comes once the box alignment is right.
class NativePreviewTestPage extends StatefulWidget {
  const NativePreviewTestPage({super.key});

  @override
  State<NativePreviewTestPage> createState() => _NativePreviewTestPageState();
}

class _NativePreviewTestPageState extends State<NativePreviewTestPage> {
  final _controller = NativeCaptureController();
  NativePreview? _preview;
  NativeFaceDetection? _face;
  StreamSubscription<NativeFaceDetection>? _sub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final preview = await _controller.initialize();
      _sub = _controller.detections().listen((d) {
        if (mounted) setState(() => _face = d);
      });
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Native detection test')),
      body: Builder(
        builder: (context) {
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Preview failed:\n$_error',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (preview == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final face = _face;
          return Stack(
            children: [
              Positioned.fill(child: NativeCameraPreview(preview: preview)),
              if (face != null && face.hasFace)
                Positioned.fill(
                  child: CustomPaint(painter: _FaceBoxPainter(face)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  face == null
                      ? 'waiting for detections…'
                      : face.hasFace
                          ? 'face ${face.boxWidth.toInt()}x${face.boxHeight.toInt()} '
                              'in ${face.imageWidth}x${face.imageHeight}'
                          : 'no face',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Maps the upright, non-mirrored face box onto the cover-fitted preview.
class _FaceBoxPainter extends CustomPainter {
  final NativeFaceDetection face;
  _FaceBoxPainter(this.face);

  @override
  void paint(Canvas canvas, Size size) {
    if (!face.hasFace || face.imageWidth == 0 || face.imageHeight == 0) return;

    final imageAspect = face.imageWidth / face.imageHeight;
    final displayAspect = size.width / size.height;

    double scaledW;
    double scaledH;
    double offsetX;
    double offsetY;
    if (imageAspect > displayAspect) {
      // image wider than display -> cover by height, overflow width
      scaledH = size.height;
      scaledW = size.height * imageAspect;
      offsetX = (size.width - scaledW) / 2;
      offsetY = 0;
    } else {
      scaledW = size.width;
      scaledH = size.width / imageAspect;
      offsetX = 0;
      offsetY = (size.height - scaledH) / 2;
    }

    final rect = Rect.fromLTWH(
      offsetX + (face.left / face.imageWidth) * scaledW,
      offsetY + (face.top / face.imageHeight) * scaledH,
      (face.boxWidth / face.imageWidth) * scaledW,
      (face.boxHeight / face.imageHeight) * scaledH,
    );

    final paint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) => old.face != face;
}
