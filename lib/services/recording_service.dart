import 'dart:io';

import 'package:record/record.dart';

class RecordingException implements Exception {
  const RecordingException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

/// Records guitar audio from the phone microphone as PCM WAV, the
/// format the analysis backend expects.
class RecordingService {
  RecordingService();

  // Created on first use: the AudioRecorder constructor touches the
  // platform channel, which must not happen in unit tests that fake
  // this service.
  AudioRecorder? _recorderInstance;

  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();

  static const RecordConfig _wavConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 44100,
    numChannels: 1,
  );

  /// The recording overwrites the same cache file each time; the most
  /// recent recording is the only one the app keeps.
  Future<String> _recordingPath() async {
    final directory = Directory.systemTemp;

    return '${directory.path}${Platform.pathSeparator}'
        'chordassist_recording.wav';
  }

  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  /// Starts a WAV recording and returns the destination path.
  Future<String> start() async {
    try {
      final path = await _recordingPath();

      await _recorder.start(_wavConfig, path: path);

      return path;
    } on RecordingException {
      rethrow;
    } catch (_) {
      throw const RecordingException(
        'Recording could not start. '
        'Check microphone access and try again.',
      );
    }
  }

  /// Stops the recording and returns the finished WAV path.
  Future<String> stop() async {
    try {
      final path = await _recorder.stop();

      if (path == null) {
        throw const RecordingException('The recording could not be saved.');
      }

      return path;
    } on RecordingException {
      rethrow;
    } catch (_) {
      throw const RecordingException('The recording could not be saved.');
    }
  }

  Future<void> cancel() async {
    try {
      await _recorderInstance?.cancel();
    } catch (_) {
      // Cancellation is best-effort.
    }
  }

  Future<void> dispose() async {
    // Drop the cached instance FIRST: a disposed platform recorder must
    // never be reused, so the next recording creates a fresh one even if
    // something disposes this service mid-lifecycle.
    final recorder = _recorderInstance;

    _recorderInstance = null;

    try {
      await recorder?.dispose();
    } catch (_) {
      // Disposal is best-effort.
    }
  }
}
