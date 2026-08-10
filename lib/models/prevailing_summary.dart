import 'chord_analysis.dart';

/// Minimum duration for a raw segment to survive into the presentation
/// summary and the Play Along cue plan.
///
/// This is a presentation parameter, not a recognition threshold, and it
/// is distinct from the frozen backend's 0.60-second segmentation
/// parameter. It was selected on the development split only
/// (threshold-first order, swept against merge-first over 0.75–1.5
/// seconds) and is frozen; held-out recordings were used afterwards only
/// for evaluation and illustration. The backend output is never modified;
/// the raw segment timeline stays available in segment details.
const double presentationMinimumDurationSec = 1.25;

/// Below this fraction of the audio duration, omitted uncertainty is
/// summarized as a brief note instead of a count.
const double presentationUncertaintyCountFraction = 0.15;

/// A presentation-layer view of an analysis.
///
/// Two derived views share one filtering pass:
///
/// * [segments] — the concise headline progression: short segments
///   removed, consecutive duplicates collapsed. Uncertain (X) regions of
///   at least the threshold are RETAINED as explicit uncertainty so the
///   summary never sounds more confident than the system.
/// * [cueSegments] — the Play Along cue plan: the same retained segments
///   but unmerged, keeping their original backend start and end times so
///   a cue never spans a removed region with synthetic timing.
class PrevailingSummary {
  const PrevailingSummary({
    required this.segments,
    required this.cueSegments,
    required this.omittedUncertainCount,
    required this.omittedUncertainDurationSec,
    required this.audioDurationSec,
  });

  /// Headline segments in playback order; consecutive surviving segments
  /// with the same label are merged into one entry.
  final List<ChordSegment> segments;

  /// Retained segments with their original backend times, unmerged.
  /// Kept separate from [segments] so the Play Along cue policy can
  /// diverge from the headline summary policy without an architecture
  /// change.
  final List<ChordSegment> cueSegments;

  /// How many uncertain (X) segments were omitted for being shorter than
  /// the presentation threshold. Longer uncertain segments are retained
  /// and are not counted here.
  final int omittedUncertainCount;

  /// Total duration of the omitted uncertain segments, in seconds.
  final double omittedUncertainDurationSec;

  final double audioDurationSec;

  bool get hasRecognizedChords {
    return segments.any((segment) => segment.isRecognizedChord);
  }

  /// Number of prevailing chord entries (retained uncertainty excluded).
  int get prevailingChordCount {
    return segments.where((segment) => segment.isRecognizedChord).length;
  }

  List<String> get displayLabels {
    return segments
        .map((segment) => segment.readableLabel)
        .toList(growable: false);
  }

  String get progressionText {
    if (!hasRecognizedChords) {
      return 'No sustained chord progression detected.';
    }

    return displayLabels.join(' → ');
  }

  /// One trailing sentence acknowledging omitted uncertainty, or an empty
  /// string when no uncertain segments were omitted.
  String get uncertaintyNote {
    if (omittedUncertainCount == 0) {
      return '';
    }

    final fraction = audioDurationSec > 0
        ? omittedUncertainDurationSec / audioDurationSec
        : 1.0;

    if (fraction < presentationUncertaintyCountFraction) {
      return omittedUncertainCount == 1
          ? 'A brief uncertain region was omitted.'
          : 'Some brief uncertain regions were omitted.';
    }

    return omittedUncertainCount == 1
        ? 'One uncertain region was omitted.'
        : '$omittedUncertainCount uncertain regions were omitted.';
  }

  String get speechText {
    if (!hasRecognizedChords) {
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

/// Builds the presentation summary from raw backend segments.
///
/// Threshold-first: each raw segment must individually reach
/// [minimumDurationSec]; survivors with the same label that end up next to
/// each other are then merged for the headline list only. This order
/// intentionally removes chords the backend fragmented into short
/// alternating pieces rather than rebuilding them, trading a small number
/// of misses for the removal of the many transient extras (documented in
/// the thesis presentation analysis).
PrevailingSummary buildPrevailingSummary(
  List<ChordSegment> segments, {
  required double audioDurationSec,
  double minimumDurationSec = presentationMinimumDurationSec,
}) {
  var omittedCount = 0;

  var omittedDuration = 0.0;

  final kept = <ChordSegment>[];

  for (final segment in segments) {
    if (segment.isNoChord) {
      continue;
    }

    if (segment.durationSec < minimumDurationSec) {
      if (segment.isUncertain) {
        omittedCount += 1;
        omittedDuration += segment.durationSec;
      }

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
    cueSegments: List.unmodifiable(kept),
    omittedUncertainCount: omittedCount,
    omittedUncertainDurationSec: omittedDuration,
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
