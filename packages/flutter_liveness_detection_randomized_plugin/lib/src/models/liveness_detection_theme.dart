import 'package:flutter/material.dart';

class LivenessDetectionTheme {
  /// Background color of the detection screen
  final Color backgroundColor;

  /// Color of the circular progress ring (completed portion)
  final Color ringProgressColor;

  /// Color of the circular progress ring (remaining portion)
  final Color ringTrackColor;

  /// Background color of the step instruction card
  final Color instructionCardColor;

  /// Text color for step instructions
  final Color instructionTextColor;

  /// Font size for step instructions
  final double instructionFontSize;

  /// Color of status text (face found / not found)
  final Color statusTextColor;

  /// Label shown when face is detected
  final String faceFoundLabel;

  /// Label shown when face is not detected
  final String faceNotFoundLabel;

  /// Text for the back button
  final String backLabel;

  const LivenessDetectionTheme({
    this.backgroundColor = Colors.black,
    this.ringProgressColor = Colors.green,
    this.ringTrackColor = Colors.grey,
    this.instructionCardColor = Colors.black,
    this.instructionTextColor = Colors.white,
    this.instructionFontSize = 24,
    this.statusTextColor = Colors.white,
    this.faceFoundLabel = 'User Face Found',
    this.faceNotFoundLabel = 'User Face Not Found...',
    this.backLabel = 'Back',
  });

  /// A light-mode preset
  const LivenessDetectionTheme.light()
      : backgroundColor = Colors.white,
        ringProgressColor = Colors.green,
        ringTrackColor = const Color(0xFFE0E0E0),
        instructionCardColor = Colors.white,
        instructionTextColor = Colors.black,
        instructionFontSize = 24,
        statusTextColor = Colors.black,
        faceFoundLabel = 'User Face Found',
        faceNotFoundLabel = 'User Face Not Found...',
        backLabel = 'Back';
}
