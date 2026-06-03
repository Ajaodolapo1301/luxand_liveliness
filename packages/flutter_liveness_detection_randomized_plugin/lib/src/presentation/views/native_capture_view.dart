import 'package:flutter/material.dart';

import '../../core/services/native_capture_service.dart';

/// Renders the native camera [Texture] full-bleed (cover), mirrored for the
/// front camera — a drop-in replacement for the `camera` plugin's
/// `CameraPreview`. All overlay UI (oval, countdown, buttons) is drawn by the
/// caller on top of this widget, so the look stays 100% Flutter.
class NativeCameraPreview extends StatelessWidget {
  final NativePreview preview;

  const NativeCameraPreview({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    // Texture renders upright (see below), so size its box with the UPRIGHT
    // aspect: for a 90/270 sensor the upright frame is portrait (h x w).
    final isQuarterTurn = (preview.rotationDegrees ~/ 90) % 2 == 1;
    final uprightWidth =
        (isQuarterTurn ? preview.height : preview.width).toDouble();
    final uprightHeight =
        (isQuarterTurn ? preview.width : preview.height).toDouble();

    Widget texture = SizedBox(
      width: uprightWidth,
      height: uprightHeight,
      child: Texture(textureId: preview.textureId),
    );

    // Flutter's external Texture already renders the camera SurfaceTexture
    // upright (it applies the SurfaceTexture transform matrix), so we must NOT
    // rotate again here — doing so double-rotates and the preview comes out
    // sideways. [rotationDegrees] is kept on the model for mapping the native
    // face box later, but is not applied to the display.
    //
    // We intentionally do NOT mirror: the preview shows the true (non-mirrored)
    // view, so moving left appears left. The native texture is already
    // non-mirrored; [preview.mirror] is retained only for later face-box
    // coordinate mapping.

    // Cover the available space while preserving the native aspect ratio,
    // matching CameraPreview's behavior in the existing overlay.
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: texture,
            ),
          ),
        );
      },
    );
  }
}
