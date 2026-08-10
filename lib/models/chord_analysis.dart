class ChordSegment {
  const ChordSegment({
    required this.start,
    required this.end,
    required this.label,
    required this.display,
    required this.confidence,
  });

  final double start;

  final double end;

  final String label;

  final String display;

  final double confidence;

  factory ChordSegment.fromJson(Map<String, dynamic> json) {
    return ChordSegment(
      start: _readDouble(json['start'], 'start'),
      end: _readDouble(json['end'], 'end'),
      label: _readString(json['label'], 'label'),
      display: _readString(json['display'], 'display'),
      confidence: _readDouble(json['confidence'], 'confidence'),
    );
  }
}

class ChordAnalysisResult {
  const ChordAnalysisResult({
    required this.segments,
    required this.progression,
    required this.ttsMessages,
    required this.method,
    required this.audioDurationSec,
    required this.latencyMs,
  });

  final List<ChordSegment> segments;

  final List<String> progression;

  final List<String> ttsMessages;

  final String method;

  final double audioDurationSec;

  final double latencyMs;

  List<ChordSegment> get harmonicSegments {
    return segments
        .where((segment) => segment.label != 'N')
        .toList(growable: false);
  }

  List<String> get readableProgression {
    return harmonicSegments
        .map((segment) => segment.display)
        .toList(growable: false);
  }

  String get progressionText {
    if (readableProgression.isEmpty) {
      return 'No reliable chord progression detected.';
    }

    return readableProgression.join(' → ');
  }

  factory ChordAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];

    if (rawSegments is! List) {
      throw const FormatException('Expected segments to be a list.');
    }

    final segments = rawSegments
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid chord segment.');
          }

          return ChordSegment.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);

    return ChordAnalysisResult(
      segments: segments,
      progression: _readStringList(json['progression']),
      ttsMessages: _readStringList(json['tts']),
      method: _readString(json['method'], 'method'),
      audioDurationSec: _readDouble(
        json['audio_duration_sec'],
        'audio_duration_sec',
      ),
      latencyMs: _readDouble(json['latency_ms'], 'latency_ms'),
    );
  }
}

double _readDouble(Object? value, String fieldName) {
  if (value is num) {
    return value.toDouble();
  }

  throw FormatException('Expected $fieldName to be numeric.');
}

String _readString(Object? value, String fieldName) {
  if (value is String) {
    return value;
  }

  throw FormatException('Expected $fieldName to be text.');
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value.whereType<String>().toList(growable: false);
}
