import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chord_analysis.dart';

class HealthCheckResult {
  const HealthCheckResult({required this.ready, required this.message});

  final bool ready;

  final String message;
}

class ChordApiException implements Exception {
  const ChordApiException(this.message, {this.connectionFailure = false});

  final String message;

  final bool connectionFailure;

  @override
  String toString() {
    return message;
  }
}

class ChordApiService {
  const ChordApiService();

  static const String baseUrl = String.fromEnvironment(
    'CHORD_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  Future<HealthCheckResult> checkHealth() async {
    try {
      final uri = Uri.parse('$baseUrl/health');

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return HealthCheckResult(
          ready: false,
          message:
              'Analysis service returned '
              'status ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        return const HealthCheckResult(
          ready: false,
          message:
              'Analysis service returned '
              'an unexpected response.',
        );
      }

      final methods = decoded['available_methods'];

      final availableMethods = methods is List
          ? methods.whereType<String>().toList()
          : <String>[];

      final serviceIsHealthy = decoded['ok'] == true;

      final basicPitchAvailable = availableMethods.contains('basic_pitch');

      if (!serviceIsHealthy) {
        return const HealthCheckResult(
          ready: false,
          message: 'Analysis service is not ready.',
        );
      }

      if (!basicPitchAvailable) {
        return const HealthCheckResult(
          ready: false,
          message:
              'Analysis service is online, '
              'but Basic Pitch is unavailable.',
        );
      }

      return const HealthCheckResult(
        ready: true,
        message: 'Analysis service is ready.',
      );
    } on TimeoutException {
      return const HealthCheckResult(
        ready: false,
        message:
            'Analysis service did not respond. '
            'Check the backend connection.',
      );
    } on FormatException {
      return const HealthCheckResult(
        ready: false,
        message:
            'Analysis service returned '
            'invalid data.',
      );
    } catch (_) {
      return const HealthCheckResult(
        ready: false,
        message:
            'Could not connect to the '
            'analysis service.',
      );
    }
  }

  Future<ChordAnalysisResult> analyzeWav({
    required Stream<List<int>> fileStream,
    required int fileLength,
    required String fileName,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/analyze-file',
      ).replace(queryParameters: const {'method': 'basic_pitch'});

      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        http.MultipartFile('file', fileStream, fileLength, filename: fileName),
      );

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw ChordApiException(_analysisErrorMessage(response));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected analysis response.');
      }

      final result = ChordAnalysisResult.fromJson(decoded);

      if (result.method != 'basic_pitch') {
        throw const FormatException('Unexpected analysis method.');
      }

      return result;
    } on TimeoutException {
      throw const ChordApiException(
        'Audio analysis timed out. '
        'Please check the backend and try again.',
        connectionFailure: true,
      );
    } on http.ClientException {
      throw const ChordApiException(
        'Could not connect to the '
        'analysis service.',
        connectionFailure: true,
      );
    } on ChordApiException {
      rethrow;
    } on FormatException {
      throw const ChordApiException(
        'The analysis service returned '
        'unexpected data.',
      );
    } catch (_) {
      throw const ChordApiException(
        'Audio analysis failed. '
        'Please try again.',
      );
    }
  }

  String _analysisErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Fall back to the HTTP status below.
    }

    return 'Audio analysis failed with '
        'status ${response.statusCode}.';
  }
}
