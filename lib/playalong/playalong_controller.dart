import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chord_analysis.dart';
import '../services/playback_service.dart';
import '../services/speech_service.dart';

enum PlayAlongState { idle, playing, paused }

/// Replays the analyzed audio and announces each recognized chord as
/// playback crosses the segment start times the backend returned.
///
/// The controller never re-runs recognition and never estimates chord
/// timing itself — it only schedules cues from the existing analysis.
/// Cues are time-aligned announcements, not sample-accurate speech.
class PlayAlongController extends ChangeNotifier {
  PlayAlongController({required this._playback, required this._speech});

  final PlaybackService _playback;

  final SpeechService _speech;

  /// Called once when playback reaches the end of the audio.
  void Function()? onFinished;

  PlayAlongState _state = PlayAlongState.idle;

  List<ChordSegment> _segments = const [];

  int _nextSegmentIndex = 0;

  double _lastPositionSeconds = 0;

  String? _currentCue;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<void>? _completedSubscription;

  bool _disposed = false;

  PlayAlongState get state => _state;

  bool get isPlaying => _state == PlayAlongState.playing;

  bool get isPaused => _state == PlayAlongState.paused;

  bool get isActive => _state != PlayAlongState.idle;

  /// The cue most recently announced, for the visual display.
  String? get currentCue => _currentCue;

  /// Loads the analyzed audio and starts announcing chord cues.
  /// Throws [PlaybackException] when the audio cannot be loaded.
  Future<void> start({
    required String audioPath,
    required List<ChordSegment> segments,
  }) async {
    if (isActive) {
      await stop();
    }

    _segments = segments;
    _nextSegmentIndex = 0;
    _lastPositionSeconds = 0;
    _currentCue = null;

    await _playback.load(audioPath);

    _positionSubscription ??= _playback.positionStream.listen(_handlePosition);

    _completedSubscription ??= _playback.completedStream.listen((_) {
      _handleCompleted();
    });

    _state = PlayAlongState.playing;
    _notify();

    await _playback.play();
  }

  Future<void> pause() async {
    if (_state != PlayAlongState.playing) {
      return;
    }

    await _playback.pause();

    _state = PlayAlongState.paused;
    _notify();
  }

  Future<void> resume() async {
    if (_state != PlayAlongState.paused) {
      return;
    }

    _state = PlayAlongState.playing;
    _notify();

    await _playback.play();
  }

  Future<void> stop() async {
    if (_state == PlayAlongState.idle) {
      return;
    }

    await _playback.stop();

    _reset();
  }

  void _handleCompleted() {
    if (_state == PlayAlongState.idle) {
      return;
    }

    _playback.stop();

    _reset();

    onFinished?.call();
  }

  void _reset() {
    _state = PlayAlongState.idle;
    _nextSegmentIndex = 0;
    _lastPositionSeconds = 0;
    _currentCue = null;

    _notify();
  }

  void _handlePosition(Duration position) {
    if (_state != PlayAlongState.playing) {
      return;
    }

    final seconds = position.inMilliseconds / 1000.0;

    // A backward jump means playback restarted or was rewound; resync
    // the pointer so cues fire again from the new position.
    if (seconds + 0.05 < _lastPositionSeconds) {
      _resyncPointer(seconds);
    }

    _lastPositionSeconds = seconds;

    ChordSegment? due;

    while (_nextSegmentIndex < _segments.length &&
        seconds >= _segments[_nextSegmentIndex].start) {
      due = _segments[_nextSegmentIndex];
      _nextSegmentIndex += 1;
    }

    // Only the most recent segment is announced: the current chord
    // takes priority over any older cue that became stale.
    if (due != null) {
      _announce(due);
    }
  }

  void _resyncPointer(double seconds) {
    var index = 0;

    while (index < _segments.length && _segments[index].start <= seconds) {
      index += 1;
    }

    _nextSegmentIndex = index;
  }

  void _announce(ChordSegment segment) {
    final cue = cueText(segment);

    if (cue == null) {
      return;
    }

    _currentCue = cue;
    _notify();

    // Fire-and-forget with queue-flush semantics on the native side:
    // a newer cue replaces one that is still being spoken.
    _speech.speak(cue).catchError((Object _) {
      // The visual cue still updates when speech is unavailable.
    });
  }

  /// The short spoken cue for a segment, or null when the segment
  /// should stay silent during Play Along.
  @visibleForTesting
  static String? cueText(ChordSegment segment) {
    if (segment.isNoChord) {
      // Repeated "no chord" announcements through silence would make
      // the feature noisy; N stays visible in segment details instead.
      return null;
    }

    if (segment.isUncertain) {
      return 'Uncertain';
    }

    return segment.display;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _positionSubscription?.cancel();
    _completedSubscription?.cancel();

    _playback.dispose();

    super.dispose();
  }
}
