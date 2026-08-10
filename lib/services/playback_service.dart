import 'dart:async';

import 'package:just_audio/just_audio.dart';

class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

/// Plays the selected WAV file (picked or recorded) locally.
///
/// Thin wrapper over just_audio so the Play Along scheduler and tests
/// can depend on a small, fakeable surface.
class PlaybackService {
  PlaybackService();

  // Created on first use: the AudioPlayer constructor touches the
  // platform channel, which must not happen in unit tests that fake
  // this service.
  AudioPlayer? _playerInstance;

  AudioPlayer get _player => _playerInstance ??= AudioPlayer();

  /// Loads a local audio file and returns its duration when known.
  Future<Duration?> load(String path) async {
    try {
      return await _player.setFilePath(path);
    } catch (_) {
      throw const PlaybackException(
        'The audio could not be loaded for playback.',
      );
    }
  }

  /// Starts or resumes playback. Does not wait for completion; watch
  /// [completedStream] instead.
  Future<void> play() async {
    try {
      unawaited(_player.play());
    } catch (_) {
      throw const PlaybackException('Playback could not start.');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {
      // Pausing is best-effort.
    }
  }

  /// Stops playback and rewinds to the beginning.
  Future<void> stop() async {
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {
      // Stopping is best-effort.
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (_) {
      // Seeking is best-effort.
    }
  }

  /// Continuous playback position updates.
  Stream<Duration> get positionStream => _player.positionStream;

  /// Emits once each time loaded audio finishes playing.
  Stream<void> get completedStream {
    return _player.processingStateStream.where(
      (state) => state == ProcessingState.completed,
    );
  }

  Future<void> dispose() async {
    try {
      await _playerInstance?.dispose();
    } catch (_) {
      // Disposal is best-effort.
    }
  }
}
