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

  bool get isNoChord {
    return label == 'N';
  }

  bool get isUncertain {
    return label == 'X';
  }

  bool get isRecognizedChord {
    return !isNoChord && !isUncertain;
  }

  String get readableLabel {
    if (isNoChord) {
      return 'No chord';
    }

    if (isUncertain) {
      return 'Uncertain segment';
    }

    return display;
  }

  double get durationSec {
    return end - start;
  }

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
  List<ChordSegment> get recognizedChordSegments {
    return segments
        .where((segment) => segment.isRecognizedChord)
        .toList(growable: false);
  }

  List<ChordSegment> get progressionSegments {
    return segments
        .where((segment) => !segment.isNoChord)
        .toList(growable: false);
  }

  int get uncertainSegmentCount {
    return segments.where((segment) => segment.label == 'X').length;
  }

  String _readableSegment(ChordSegment segment) {
    return segment.readableLabel;
  }

  List<String> get readableProgression {
    return progressionSegments.map(_readableSegment).toList(growable: false);
  }

  String get progressionText {
    if (readableProgression.isEmpty) {
      return 'No reliable chord progression detected.';
    }

    return readableProgression.join(' → ');
  }

  String get speechText {
    if (readableProgression.isEmpty) {
      return 'No reliable chord progression '
          'was detected.';
    }

    final chordCount = recognizedChordSegments.length;

    final uncertaintyCount = uncertainSegmentCount;

    final buffer = StringBuffer();

    buffer.write(
      'Detected $chordCount recognized '
      'chord segments',
    );

    if (uncertaintyCount > 0) {
      buffer.write(
        ' and $uncertaintyCount uncertain '
        'segments',
      );
    }

    buffer.write('. The detected progression is ');

    buffer.write(readableProgression.join(', '));

    buffer.write('.');

    return buffer.toString();
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
