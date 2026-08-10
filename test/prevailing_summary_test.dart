import 'dart:convert';
import 'dart:io';

import 'package:chords_finder/models/chord_analysis.dart';
import 'package:chords_finder/models/prevailing_summary.dart';
import 'package:flutter_test/flutter_test.dart';

ChordSegment segment(
  String label, {
  String? display,
  double start = 0,
  double end = 2,
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

ChordAnalysisResult loadFixture(String name) {
  final file = File('test/fixtures/$name');

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  return ChordAnalysisResult.fromJson(json);
}

void main() {
  group('buildPrevailingSummary rules', () {
    test('drops N, X, and chords shorter than the threshold', () {
      final summary = buildPrevailingSummary([
        segment('N', start: 0, end: 2),
        segment('G:sus4', display: 'G sus4', start: 2, end: 2.5),
        segment('C:maj', display: 'C major', start: 2.5, end: 6),
        segment('X', start: 6, end: 6.7),
        segment('G:maj', display: 'G major', start: 6.7, end: 10),
      ], audioDurationSec: 10);

      expect(summary.displayLabels, ['C major', 'G major']);
      expect(summary.droppedUncertainCount, 1);
      expect(summary.droppedUncertainDurationSec, closeTo(0.7, 1e-9));
    });

    test('thresholds each raw segment before merging', () {
      // Two short fragments of the same chord must not be rebuilt into
      // a prevailing chord by merging: threshold-first drops them both.
      final summary = buildPrevailingSummary([
        segment('A:min7', display: 'A minor seventh', start: 0, end: 1),
        segment('A:min7', display: 'A minor seventh', start: 1, end: 2),
      ], audioDurationSec: 2);

      expect(summary.segments, isEmpty);
    });

    test('merges surviving neighbours with the same label', () {
      final summary = buildPrevailingSummary([
        segment('D:7', display: 'D dominant seventh', start: 0, end: 2),
        segment('X', start: 2, end: 2.4),
        segment('D:7', display: 'D dominant seventh', start: 2.4, end: 4.4),
        segment('G:maj', display: 'G major', start: 4.4, end: 6.4),
      ], audioDurationSec: 6.4);

      expect(summary.displayLabels, ['D dominant seventh', 'G major']);
      expect(summary.segments.first.start, 0);
      expect(summary.segments.first.end, 4.4);
    });

    test('speaks a short note for minor uncertainty', () {
      final summary = buildPrevailingSummary([
        segment('C:maj', display: 'C major', start: 0, end: 8),
        segment('X', start: 8, end: 8.5),
      ], audioDurationSec: 10);

      expect(
        summary.speechText,
        'The detected progression is C major. '
        'Some short regions were uncertain.',
      );
    });

    test('speaks a count when uncertainty dominates', () {
      final summary = buildPrevailingSummary([
        segment('C:maj', display: 'C major', start: 0, end: 2),
        segment('X', start: 2, end: 4),
        segment('X', start: 4, end: 6),
      ], audioDurationSec: 6);

      expect(
        summary.speechText,
        'The detected progression is C major. '
        '2 regions were uncertain.',
      );
    });

    test('handles an empty prevailing list', () {
      final summary = buildPrevailingSummary([
        segment('N', start: 0, end: 2),
        segment('G:sus4', display: 'G sus4', start: 2, end: 2.5),
      ], audioDurationSec: 2.5);

      expect(
        summary.speechText,
        'No sustained chord progression was detected.',
      );
    });
  });

  group('archived backend fixtures', () {
    // These fixtures are copies of archived scientific responses:
    // held_standard_01 from the formal held-out run (commit f9fa039) and
    // dev_clean_01 from the frozen development run. The expectations
    // document the presentation transformation against real output.
    test('dev_clean_01 summarizes to the reference progression', () {
      final result = loadFixture('dev_clean_01_basic_pitch_response.json');

      final summary = result.prevailingSummary;

      expect(summary.displayLabels, [
        'C major',
        'G major',
        'A minor',
        'E minor',
      ]);

      expect(
        summary.speechText,
        'The detected progression is '
        'C major, G major, A minor, E minor. '
        'Some short regions were uncertain.',
      );
    });

    test('held_standard_01 summarizes to the reference progression', () {
      final result = loadFixture('held_standard_01_basic_pitch_response.json');

      final summary = result.prevailingSummary;

      expect(summary.displayLabels, [
        'G major',
        'B minor',
        'C major',
        'D dominant seventh',
      ]);
    });

    test('raw output is never modified by the summary view', () {
      final result = loadFixture('dev_clean_01_basic_pitch_response.json');

      final rawCount = result.segments.length;

      result.prevailingSummary;

      expect(result.segments.length, rawCount);
      expect(result.segments.length, greaterThan(10));
    });
  });
}
