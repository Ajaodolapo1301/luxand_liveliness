import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

class LuxandApi {
  static const String _baseUrl = 'https://api.luxand.cloud';

  final String apiKey;

  const LuxandApi({required this.apiKey});

  Future<({bool isReal, double score})> checkLiveness(File imageFile) async {
    final uri = Uri.parse('$_baseUrl/photo/liveness');
    final fixedFile = await _fixRotation(imageFile);

    final request = http.MultipartRequest('POST', uri)
      ..headers['token'] = apiKey
      ..files.add(await http.MultipartFile.fromPath('photo', fixedFile.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    dev.log('[LuxandApi] status: ${response.statusCode}', name: 'LuxandApi');
    dev.log('[LuxandApi] body: ${response.body}', name: 'LuxandApi');

    if (response.statusCode != 200) {
      throw Exception(
        'HTTP ${response.statusCode} — ${response.body.isNotEmpty ? response.body : "no body"}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['status'] != 'success') {
      throw Exception('Luxand error: ${json['message'] ?? response.body}');
    }

    return (
      isReal: (json['result'] as String?) == 'real',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Future<File> _fixRotation(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;
      final fixed = img.bakeOrientation(decoded);
      final fixedPath = '${file.path}_fixed.jpg';
      return File(fixedPath)
        ..writeAsBytesSync(img.encodeJpg(fixed, quality: 90));
    } catch (e) {
      dev.log('[LuxandApi] rotation fix failed: $e', name: 'LuxandApi');
      return file;
    }
  }
}
