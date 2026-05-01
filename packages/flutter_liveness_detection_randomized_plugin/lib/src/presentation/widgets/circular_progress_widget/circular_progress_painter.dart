import 'package:flutter/material.dart';

/// SmileID-style overlay painter:
/// 1. Semi-transparent dark mask with an oval cutout
/// 2. Solid oval border track
/// 3. Smooth continuous arc stroke that fills clockwise as progress increases
class SmileIdOverlayPainter extends CustomPainter {
  final Color overlayColor;
  final Color ringTrackColor;
  final Color ringProgressColor;
  final double progress;        // 0.0 → 1.0
  final double ovalWidth;
  final double ovalHeight;
  final double ringThickness;
  final double verticalOffset;

  const SmileIdOverlayPainter({
    required this.overlayColor,
    required this.ringTrackColor,
    required this.ringProgressColor,
    required this.progress,
    required this.ovalWidth,
    required this.ovalHeight,
    this.ringThickness = 5,
    this.verticalOffset = -40,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + verticalOffset;

    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: ovalWidth,
      height: ovalHeight,
    );

    // 1. Dark overlay with oval cutout (even-odd rule)
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlayPath, Paint()..color = overlayColor);

    // 2. Full oval track (thin, faint)
    final trackPaint = Paint()
      ..color = ringTrackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringThickness
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(ovalRect, trackPaint);

    // 3. Progress arc — extract partial path from oval using PathMetrics
    if (progress > 0) {
      final ovalPath = Path()..addOval(ovalRect);
      final metric = ovalPath.computeMetrics().first;

      // PathMetrics starts at 3 o'clock; rotate start to 12 o'clock by offsetting by -¼
      final totalLength = metric.length;
      final startOffset = totalLength * 0.75; // 12 o'clock = 75% through the path
      final arcLength = totalLength * progress.clamp(0.0, 1.0);

      Path progressPath;
      if (startOffset + arcLength <= totalLength) {
        progressPath = metric.extractPath(startOffset, startOffset + arcLength);
      } else {
        // Wraps around — two segments
        final seg1 = metric.extractPath(startOffset, totalLength);
        final seg2 = metric.extractPath(0, (startOffset + arcLength) - totalLength);
        progressPath = Path()
          ..addPath(seg1, Offset.zero)
          ..addPath(seg2, Offset.zero);
      }

      final progressPaint = Paint()
        ..color = ringProgressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringThickness
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(progressPath, progressPaint);
    }
  }

  @override
  bool shouldRepaint(SmileIdOverlayPainter old) =>
      old.progress != progress ||
      old.ringProgressColor != ringProgressColor ||
      old.overlayColor != overlayColor ||
      old.ringTrackColor != ringTrackColor;
}
