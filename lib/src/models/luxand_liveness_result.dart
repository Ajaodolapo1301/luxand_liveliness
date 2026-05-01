import 'dart:io';

/// The result returned by [LuxandLiveness.verify].
///
/// - Returns `null`  → user cancelled / abandoned the challenges.
/// - [isSuccess] `true`  → Luxand responded successfully; check [isReal] and [score].
/// - [isSuccess] `false` → an error occurred; check [error].
class LuxandLivenessResult {
  final bool isSuccess;

  /// Whether Luxand classified the face as a real (live) person.
  final bool? isReal;

  /// Luxand confidence score (0.0 – 1.0).
  final double? score;

  /// The captured face image file.
  final File? imageFile;

  /// Error message when [isSuccess] is `false`.
  final String? error;

  const LuxandLivenessResult._({
    required this.isSuccess,
    this.isReal,
    this.score,
    this.imageFile,
    this.error,
  });

  factory LuxandLivenessResult.success({
    required bool isReal,
    required double score,
    required File imageFile,
  }) =>
      LuxandLivenessResult._(
        isSuccess: true,
        isReal: isReal,
        score: score,
        imageFile: imageFile,
      );

  factory LuxandLivenessResult.failure(String error) =>
      LuxandLivenessResult._(isSuccess: false, error: error);

  @override
  String toString() => isSuccess
      ? 'LuxandLivenessResult(isReal: $isReal, score: $score)'
      : 'LuxandLivenessResult(error: $error)';
}
