import 'package:chords_finder/models/chord_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

ChordSegment segment(
  String label, {
  String? display,
  double start = 0,
  double end = 1,
  double confidence = 0.9,
}) {
  return ChordSegment(
    start: start,
    end: end,
    label: label,
    display: display ?? label,
    confidence: confidence,
  );
}

void main() {
  group('ChordSegment', () {
    test('classifies N, X, and recognized chords', () {
      expect(segment('N').isNoChord, isTrue);
      expect(segment('N').isRecognizedChord, isFalse);

      expect(segment('X').isUncertain, isTrue);
      expect(segment('X').isRecognizedChord, isFalse);

      expect(segment('C:maj').isRecognizedChord, isTrue);
    });

    test('readableLabel never exposes raw N or X', () {
      expect(segment('N').readableLabel, 'No chord');
      expect(segment('X').readableLabel, 'Uncertain segment');
      expect(segment('C:maj', display: 'C major').readableLabel, 'C major');
    });
  });

  group('ChordAnalysisResult formatting', () {
    final result = ChordAnalysisResult(
      segments: [
        segment('C:maj', display: 'C major', start: 0, end: 2),
        segment('N', start: 2, end: 3),
        segment('G:maj', display: 'G major', start: 3, end: 5),
        segment('X', start: 5, end: 6),
        segment('A:min', display: 'A minor', start: 6, end: 8),
      ],
      progression: const ['C:maj', 'G:maj', 'A:min'],
      ttsMessages: const [],
      method: 'basic_pitch',
      audioDurationSec: 8,
      latencyMs: 900,
    );

    test('progression keeps X as Uncertain segment and drops N', () {
      expect(result.readableProgression, [
        'C major',
        'G major',
        'Uncertain segment',
        'A minor',
      ]);
    });

    test('progression text joins readable labels', () {
      expect(
        result.progressionText,
        'C major → G major → Uncertain segment → A minor',
      );
    });

    test('speech distinguishes recognition from uncertainty', () {
      expect(
        result.speechText,
        'Detected 3 recognized chord segments '
        'and 1 uncertain segment. '
        'The detected progression is '
        'C major, G major, Uncertain segment, A minor.',
      );
    });

    test('singular and plural segment counts read correctly', () {
      final single = ChordAnalysisResult(
        segments: [segment('C:maj', display: 'C major')],
        progression: const ['C:maj'],
        ttsMessages: const [],
        method: 'basic_pitch',
        audioDurationSec: 1,
        latencyMs: 100,
      );

      expect(
        single.speechText,
        'Detected 1 recognized chord segment. '
        'The detected progression is C major.',
      );
    });

    test('empty analysis reports no reliable progression', () {
      const empty = ChordAnalysisResult(
        segments: [],
        progression: [],
        ttsMessages: [],
        method: 'basic_pitch',
        audioDurationSec: 0,
        latencyMs: 0,
      );

      expect(empty.progressionText, 'No reliable chord progression detected.');

      expect(empty.speechText, 'No reliable chord progression was detected.');
    });
  });

  group('ChordAnalysisResult.fromJson', () {
    test('parses a backend response', () {
      final result = ChordAnalysisResult.fromJson({
        'segments': [
          {
            'start': 0.0,
            'end': 2.4,
            'label': 'C:maj',
            'display': 'C major',
            'confidence': 0.91,
          },
        ],
        'progression': ['C:maj'],
        'tts': ['C major'],
        'method': 'basic_pitch',
        'audio_duration_sec': 2.4,
        'latency_ms': 850.0,
      });

      expect(result.segments, hasLength(1));
      expect(result.segments.first.display, 'C major');
      expect(result.method, 'basic_pitch');
    });

    test('rejects malformed segments', () {
      expect(
        () => ChordAnalysisResult.fromJson({
          'segments': ['not a segment'],
          'method': 'basic_pitch',
          'audio_duration_sec': 0,
          'latency_ms': 0,
        }),
        throwsFormatException,
      );
    });

    test('rejects missing numeric fields', () {
      expect(
        () => ChordAnalysisResult.fromJson({
          'segments': [],
          'method': 'basic_pitch',
          'audio_duration_sec': 'soon',
          'latency_ms': 0,
        }),
        throwsFormatException,
      );
    });
  });
}
