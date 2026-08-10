import 'dart:async';

import 'package:chords_finder/models/chord_analysis.dart';
import 'package:chords_finder/playalong/playalong_controller.dart';
import 'package:chords_finder/services/playback_service.dart';
import 'package:chords_finder/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlaybackService extends PlaybackService {
  final StreamController<Duration> positions =
      StreamController<Duration>.broadcast(sync: true);

  final StreamController<void> completions = StreamController<void>.broadcast(
    sync: true,
  );

  final List<String> calls = [];

  @override
  Future<Duration?> load(String path) async {
    calls.add('load:$path');

    return const Duration(seconds: 12);
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<void> get completedStream => completions.stream;

  @override
  Future<void> dispose() async {}
}

class _FakeSpeechService extends SpeechService {
  final List<String> spoken = [];

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }
}

ChordSegment segment(
  double start,
  double end,
  String label, {
  String? display,
}) {
  return ChordSegment(
    start: start,
    end: end,
    label: label,
    display: display ?? label,
    confidence: 0.9,
  );
}

void main() {
  late _FakePlaybackService playback;
  late _FakeSpeechService speech;
  late PlayAlongController controller;

  final segments = [
    segment(0.8, 4.1, 'C:maj', display: 'C major'),
    segment(4.1, 7.7, 'G:maj', display: 'G major'),
    segment(7.7, 9.0, 'X', display: 'X'),
    segment(9.0, 10.0, 'N', display: 'N'),
    segment(10.0, 12.0, 'A:min', display: 'A minor'),
  ];

  setUp(() {
    playback = _FakePlaybackService();
    speech = _FakeSpeechService();

    controller = PlayAlongController(playback: playback, speech: speech);
  });

  Future<void> startControllerWith(List<ChordSegment> list) async {
    await controller.start(audioPath: '/cache/audio.wav', segments: list);
  }

  void emitSeconds(double seconds) {
    playback.positions.add(Duration(milliseconds: (seconds * 1000).round()));
  }

  group('PlayAlongController', () {
    test('start loads the audio and begins playing', () async {
      await startControllerWith(segments);

      expect(playback.calls, contains('load:/cache/audio.wav'));
      expect(playback.calls, contains('play'));
      expect(controller.isPlaying, isTrue);
    });

    test('announces each chord once as playback crosses its start', () async {
      await startControllerWith(segments);

      emitSeconds(0.2);
      expect(speech.spoken, isEmpty);

      emitSeconds(0.9);
      expect(speech.spoken, ['C major']);

      emitSeconds(2.0);
      emitSeconds(3.9);
      expect(speech.spoken, ['C major']);

      emitSeconds(4.2);
      expect(speech.spoken, ['C major', 'G major']);
    });

    test('announces X as Uncertain and never announces N', () async {
      await startControllerWith(segments);

      emitSeconds(7.8);
      expect(speech.spoken.last, 'Uncertain');

      emitSeconds(9.4);
      expect(speech.spoken.last, 'Uncertain');

      emitSeconds(10.1);
      expect(speech.spoken.last, 'A minor');

      expect(speech.spoken, isNot(contains('N')));
      expect(speech.spoken, isNot(contains('No chord')));
    });

    test('skipping ahead announces only the current chord', () async {
      await startControllerWith(segments);

      // Position jumps straight into the third segment; the stale
      // C major and G major cues must not queue up.
      emitSeconds(8.0);

      expect(speech.spoken, ['Uncertain']);
    });

    test('does not announce cues while paused', () async {
      await startControllerWith(segments);

      await controller.pause();

      emitSeconds(1.0);

      expect(speech.spoken, isEmpty);
      expect(controller.isPaused, isTrue);

      await controller.resume();

      emitSeconds(1.1);

      expect(speech.spoken, ['C major']);
    });

    test('a backward jump resyncs cues to the new position', () async {
      await startControllerWith(segments);

      emitSeconds(4.5);
      expect(speech.spoken, ['G major']);

      // Playback rewinds to the beginning.
      emitSeconds(0.0);
      emitSeconds(0.9);

      expect(speech.spoken, ['G major', 'C major']);
    });

    test('completion resets state and notifies the app', () async {
      var finished = 0;

      controller.onFinished = () => finished += 1;

      await startControllerWith(segments);

      playback.completions.add(null);

      expect(finished, 1);
      expect(controller.isActive, isFalse);
      expect(controller.currentCue, isNull);
    });

    test('stop returns to idle and clears the cue', () async {
      await startControllerWith(segments);

      emitSeconds(0.9);
      expect(controller.currentCue, 'C major');

      await controller.stop();

      expect(controller.isActive, isFalse);
      expect(controller.currentCue, isNull);
      expect(playback.calls, contains('stop'));
    });

    test('restarting after completion announces cues again', () async {
      await startControllerWith(segments);

      emitSeconds(0.9);
      expect(speech.spoken, ['C major']);

      playback.completions.add(null);

      await startControllerWith(segments);

      emitSeconds(0.9);

      expect(speech.spoken, ['C major', 'C major']);
    });
  });
}
