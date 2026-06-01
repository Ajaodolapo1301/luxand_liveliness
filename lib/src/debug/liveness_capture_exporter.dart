import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Copies liveness captures to a folder visible in Samsung "My Files" / Downloads.
abstract final class LivenessCaptureExporter {
  static const String folderName = 'luxand_liveness_debug';

  /// Returns export directory path, or null if export failed.
  static Future<String?> export({
    required String rawCapturePath,
    String? fixedCapturePath,
  }) async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads == null) return null;

      final outDir = Directory('${downloads.path}/$folderName');
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final rawOut = '${outDir.path}/capture_$stamp.jpg';
      await File(rawCapturePath).copy(rawOut);

      String? fixedOut;
      final fixed = fixedCapturePath ?? '${rawCapturePath}_fixed.jpg';
      if (File(fixed).existsSync()) {
        fixedOut = '${outDir.path}/capture_${stamp}_luxand_upload.jpg';
        await File(fixed).copy(fixedOut);
      }

      // ignore: avoid_print
      print(
        '[LuxandDebug] Captures exported to ${outDir.path}\n'
        '  raw: $rawOut\n'
        '  upload: ${fixedOut ?? "(no _fixed file)"}',
      );
      return outDir.path;
    } catch (e) {
      // ignore: avoid_print
      print('[LuxandDebug] Export failed: $e');
      return null;
    }
  }
}
