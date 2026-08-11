import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/recording_service.dart';

enum RecordingPhase { idle, recording, stopping }

class RecordingResult {
  const RecordingResult({
    required this.path,
    required this.duration,
    required this.autoStopped,
  });

  /// Path of the finished WAV file.
  final String path;

  final Duration duration;

  /// Whether the safety timeout stopped the recording.
  final bool autoStopped;
}

/// Drives one guitar recording: elapsed time, manual stop, and the
/// safety timeout that stops the recording automatically.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required this._service,
    this.maxDuration = const Duration(seconds: 60),
  });

  final RecordingService _service;

  /// Safety limit: recording never runs longer than this.
  final Duration maxDuration;

  /// Elapsed time advances in these steps, which keeps the controller
  /// deterministic under fake-time tests.
  static const Duration tickInterval = Duration(milliseconds: 100);

  /// Called when the safety timeout stopped the recording; the result
  /// is identical to a manual stop apart from
  /// [RecordingResult.autoStopped].
  void Function(RecordingResult result)? onAutoStopped;

  /// Called when recording fails while in progress.
  void Function(String message)? onRecordingError;

  RecordingPhase _phase = RecordingPhase.idle;

  Timer? _ticker;

  Duration _elapsed = Duration.zero;

  bool _disposed = false;

  RecordingPhase get phase => _phase;

  Duration get elapsed => _elapsed;

  bool get isRecording => _phase == RecordingPhase.recording;

  Duration get remaining {
    final left = maxDuration - _elapsed;

    return left.isNegative ? Duration.zero : left;
  }

  /// Starts recording. Throws [RecordingException] when the recorder
  /// cannot start (for example without microphone permission).
  Future<void> start() async {
    if (_phase != RecordingPhase.idle) {
      return;
    }

    await _service.start();

    _phase = RecordingPhase.recording;
    _elapsed = Duration.zero;

    _ticker = Timer.periodic(tickInterval, (_) {
      _handleTick();
    });

    _notify();
  }

  void _handleTick() {
    if (_phase != RecordingPhase.recording) {
      return;
    }

    _elapsed += tickInterval;

    if (_elapsed >= maxDuration) {
      _autoStop();
      return;
    }

    // Only rebuild listeners on whole-second boundaries; the visible
    // counter shows seconds.
    if (_elapsed.inMilliseconds % 1000 == 0) {
      _notify();
    }
  }

  Future<void> _autoStop() async {
    final RecordingResult result;

    try {
      result = await _finishRecording(autoStopped: true);
    } on RecordingException catch (error) {
      onRecordingError?.call(error.message);
      return;
    }

    onAutoStopped?.call(result);
  }

  /// Stops the recording and returns the finished result.
  Future<RecordingResult> stop() {
    return _finishRecording(autoStopped: false);
  }

  Future<RecordingResult> _finishRecording({required bool autoStopped}) async {
    if (_phase != RecordingPhase.recording) {
      throw const RecordingException('No recording is in progress.');
    }

    _phase = RecordingPhase.stopping;

    _ticker?.cancel();
    _ticker = null;

    if (_elapsed > maxDuration) {
      _elapsed = maxDuration;
    }

    _notify();

    try {
      final path = await _service.stop();

      _phase = RecordingPhase.idle;
      _notify();

      return RecordingResult(
        path: path,
        duration: _elapsed,
        autoStopped: autoStopped,
      );
    } on RecordingException {
      _phase = RecordingPhase.idle;
      _notify();

      rethrow;
    }
  }

  /// Abandons the current recording without keeping the file.
  Future<void> cancel() async {
    if (_phase == RecordingPhase.idle) {
      return;
    }

    _ticker?.cancel();
    _ticker = null;

    await _service.cancel();

    _phase = RecordingPhase.idle;
    _elapsed = Duration.zero;

    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;

    _ticker?.cancel();
    _ticker = null;

    if (_phase == RecordingPhase.recording) {
      _service.cancel();
    }

    // The service is shared across recording sessions and owned by the
    // home screen; disposing it here would break every later recording
    // (the platform recorder cannot be reused after disposal).

    super.dispose();
  }
}
