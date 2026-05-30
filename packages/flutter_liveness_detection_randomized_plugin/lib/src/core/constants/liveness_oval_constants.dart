/// Shared oval geometry for overlay drawing and face-in-oval hit testing.
abstract final class LivenessOvalConstants {
  /// Oval width in logical pixels (was 280).
  static const double width = 320;

  /// Oval height in logical pixels (was 370).
  static const double height = 420;

  /// Vertical shift applied to center the oval on screen.
  static const double verticalOffset = -40;

  /// Ellipse tolerance multiplier — values > 1 allow faces slightly outside the ring.
  static const double inOvalTolerance = 1.3;
}
