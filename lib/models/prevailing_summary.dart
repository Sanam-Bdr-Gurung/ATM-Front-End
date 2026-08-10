import 'chord_analysis.dart';

/// Minimum duration for a raw segment to count as a prevailing chord in
/// spoken summaries and Play Along cues.
///
/// This is a presentation parameter, not a recognition threshold. It was
/// selected on the development split only (threshold-first order, swept
/// against merge-first over 0.75–1.5 seconds) and was never tuned on
/// held-out data. The backend output is never modified; the raw segment
/// timeline stays available in segment details.
const double prevailingMinimumChordDurationSec = 1.25;

/// Below this fraction of the audio duration, removed uncertainty is
/// summarized as "some short regions" instead of a count.
const double prevailingUncertaintyCountFraction = 0.15;

/// A presentation-layer view of an analysis: the chords that remain after
/// short transients, uncertain regions and no-chord regions are removed.
class PrevailingSummary {
  const PrevailingSummary({
    required this.segments,
    required this.droppedUncertainCount,
    required this.droppedUncertainDurationSec,
    required this.audioDurationSec,
  });

  /// Prevailing chord segments in playback order. Consecutive surviving
  /// segments with the same label are merged into one entry.
  final List<ChordSegment> segments;

  /// How many uncertain (X) segments the raw timeline contained.
  final int droppedUncertainCount;

  /// Total duration of the removed uncertain segments, in seconds.
  final double droppedUncertainDurationSec;

  final double audioDurationSec;

  List<String> get displayLabels {
    return segments.map((segment) => segment.display).toList(growable: false);
  }

  String get progressionText {
    if (segments.isEmpty) {
      return 'No sustained chord progression detected.';
    }

    return displayLabels.join(' → ');
  }

  /// One trailing sentence acknowledging removed uncertainty, or an empty
  /// string when the raw timeline contained no uncertain segments.
  String get uncertaintyNote {
    if (droppedUncertainCount == 0) {
      return '';
    }

    final fraction = audioDurationSec > 0
        ? droppedUncertainDurationSec / audioDurationSec
        : 1.0;

    if (fraction < prevailingUncertaintyCountFraction) {
      return 'Some short regions were uncertain.';
    }

    if (droppedUncertainCount == 1) {
      return 'One region was uncertain.';
    }

    return '$droppedUncertainCount regions were uncertain.';
  }

  String get speechText {
    if (segments.isEmpty) {
      final note = uncertaintyNote;

      return note.isEmpty
          ? 'No sustained chord progression was detected.'
          : 'No sustained chord progression was detected. $note';
    }

    final buffer = StringBuffer();

    buffer.write('The detected progression is ');

    buffer.write(displayLabels.join(', '));

    buffer.write('.');

    final note = uncertaintyNote;

    if (note.isNotEmpty) {
      buffer.write(' $note');
    }

    return buffer.toString();
  }
}

/// Builds the prevailing summary from raw backend segments.
///
/// Threshold-first: each raw segment must individually reach
/// [minimumDurationSec]; survivors with the same label that end up next to
/// each other are then merged. This order intentionally removes chords the
/// backend fragmented into short alternating pieces rather than rebuilding
/// them, trading a small number of misses for the removal of the many
/// transient extras (documented in the thesis presentation analysis).
PrevailingSummary buildPrevailingSummary(
  List<ChordSegment> segments, {
  required double audioDurationSec,
  double minimumDurationSec = prevailingMinimumChordDurationSec,
}) {
  var uncertainCount = 0;

  var uncertainDuration = 0.0;

  final kept = <ChordSegment>[];

  for (final segment in segments) {
    if (segment.isUncertain) {
      uncertainCount += 1;
      uncertainDuration += segment.durationSec;
      continue;
    }

    if (!segment.isRecognizedChord) {
      continue;
    }

    if (segment.durationSec < minimumDurationSec) {
      continue;
    }

    kept.add(segment);
  }

  final merged = <ChordSegment>[];

  for (final segment in kept) {
    if (merged.isNotEmpty && merged.last.label == segment.label) {
      final previous = merged.removeLast();

      final previousDuration = previous.durationSec;

      final combinedDuration = previousDuration + segment.durationSec;

      merged.add(
        ChordSegment(
          start: previous.start,
          end: segment.end,
          label: previous.label,
          display: previous.display,
          confidence: combinedDuration > 0
              ? (previous.confidence * previousDuration +
                        segment.confidence * segment.durationSec) /
                    combinedDuration
              : previous.confidence,
        ),
      );

      continue;
    }

    merged.add(segment);
  }

  return PrevailingSummary(
    segments: List.unmodifiable(merged),
    droppedUncertainCount: uncertainCount,
    droppedUncertainDurationSec: uncertainDuration,
    audioDurationSec: audioDurationSec,
  );
}

extension PrevailingSummaryView on ChordAnalysisResult {
  /// The presentation-layer summary used for spoken results and Play
  /// Along cues. The raw [segments] list is unchanged and remains the
  /// source for segment details.
  PrevailingSummary get prevailingSummary {
    return buildPrevailingSummary(segments, audioDurationSec: audioDurationSec);
  }
}
