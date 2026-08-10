import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class HealthCheckResult {
  const HealthCheckResult({
    required this.ready,
    required this.message,
  });

  final bool ready;

  final String message;
}

class ChordApiService {
  const ChordApiService();

  static const String baseUrl = String.fromEnvironment(
    'CHORD_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  Future<HealthCheckResult> checkHealth() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/health',
      );

      final response = await http
          .get(uri)
          .timeout(
        const Duration(
          seconds: 5,
        ),
      );

      if (response.statusCode != 200) {
        return HealthCheckResult(
          ready: false,
          message:
          'Analysis service returned '
              'status ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(
        response.body,
      );

      if (decoded is! Map<String, dynamic>) {
        return const HealthCheckResult(
          ready: false,
          message:
          'Analysis service returned '
              'an unexpected response.',
        );
      }

      final methods = decoded[
      'available_methods'
      ];

      final availableMethods = methods is List
          ? methods
          .whereType<String>()
          .toList()
          : <String>[];

      final serviceIsHealthy =
          decoded['ok'] == true;

      final basicPitchAvailable =
      availableMethods.contains(
        'basic_pitch',
      );

      if (!serviceIsHealthy) {
        return const HealthCheckResult(
          ready: false,
          message:
          'Analysis service is not ready.',
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
        message:
        'Analysis service is ready.',
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
}