import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/speech_service.dart';
import '../services/voice_command_service.dart';

/// What the application wants the voice session to do after a phrase
/// has been handled.
enum VoiceFlowOutcome {
  /// Keep the session running and listen for the next command.
  continueListening,

  /// The handler has taken over the microphone or the screen (file
  /// picker, recording, playback). The session pauses without any
  /// extra announcement; the app resumes it explicitly later.
  suspendListening,

  /// End the session. The handler has already spoken any farewell.
  stopListening,
}

enum VoiceControlState {
  /// No session has run yet.
  idle,

  /// Startup announcements or the permission flow are in progress.
  starting,

  /// The speech recognizer is active.
  listening,

  /// A recognized phrase is being handled (including spoken replies).
  processing,

  /// The session is stopped but can be resumed with the Listen button.
  paused,

  /// Voice control cannot run (no permission or no recognizer).
  unavailable,
}

/// Runs bounded, half-duplex voice-command sessions.
///
/// The contract is strict: ChordAssist never intentionally speaks while
/// the speech recognizer is listening. Every announcement uses
/// [SpeechService.speakAndWait] before a listen begins.
class VoiceCommandController extends ChangeNotifier {
  VoiceCommandController({
    required this._speechService,
    required this._voiceService,
    required this._onPhrase,
  });

  final SpeechService _speechService;

  final VoiceCommandService _voiceService;

  final Future<VoiceFlowOutcome> Function(String phrase) _onPhrase;

  static const String firstLaunchExplanation =
      'Welcome to ChordAssist. '
      'Voice control and guitar recording use the microphone. '
      'Android will now ask for microphone access. '
      'You can grant or deny this permission. '
      'Without microphone access, you can still use the accessible '
      'controls to analyze an existing audio file.';

  static const String permissionGrantedAnnouncement =
      'Microphone access granted. '
      'ChordAssist is ready. '
      'Listening for a command.';

  static const String returningLaunchAnnouncement =
      'ChordAssist ready. '
      'Listening for a command. '
      'Say help to hear available commands.';

  static const String microphoneDeniedMessage =
      'Microphone access was not granted. '
      'Voice control and guitar recording are unavailable. '
      'You can still analyze an existing WAV file.';

  VoiceControlState _state = VoiceControlState.idle;

  String _statusMessage = 'Voice control has not started.';

  int _consecutiveFailures = 0;

  bool _suspendRequested = false;

  bool _disposed = false;

  VoiceControlState get state => _state;

  String get statusMessage => _statusMessage;

  bool get isSessionActive {
    return _state == VoiceControlState.starting ||
        _state == VoiceControlState.listening ||
        _state == VoiceControlState.processing;
  }

  /// Whether the fallback Listen button should be enabled.
  bool get canStartListening => !isSessionActive;

  /// Voice-first startup: called automatically when the app launches.
  ///
  /// On first launch (microphone permission missing) the app explains
  /// the upcoming Android permission dialog before showing it.
  Future<void> startLaunchSession() {
    return _startSession(readyAnnouncement: returningLaunchAnnouncement);
  }

  /// Fallback/recovery entry point for the accessible Listen button and
  /// for resuming after an app action (file picker, analysis) finishes.
  Future<void> startManualSession({
    String announcement = 'Listening for a command.',
  }) {
    return _startSession(readyAnnouncement: announcement);
  }

  Future<void> _startSession({required String readyAnnouncement}) async {
    if (isSessionActive) {
      return;
    }

    _setState(VoiceControlState.starting, 'Starting voice control.');

    final bool hasPermission;

    try {
      hasPermission = await _voiceService.hasMicrophonePermission();
    } on VoiceCommandException catch (error) {
      _setState(VoiceControlState.unavailable, error.message);
      return;
    }

    if (!hasPermission) {
      // Explain the upcoming Android dialog before it appears. The
      // dialog itself belongs to Android, so first-time interaction may
      // rely on Voice Access or TalkBack.
      await _speakSafely(firstLaunchExplanation, wait: true);

      final bool granted;

      try {
        granted = await _voiceService.requestMicrophonePermission();
      } on VoiceCommandException catch (error) {
        _setState(VoiceControlState.unavailable, error.message);
        return;
      }

      if (!granted) {
        _setState(
          VoiceControlState.unavailable,
          'Microphone access was not granted. '
          'Voice control is unavailable, but you can still '
          'analyze an existing WAV file.',
        );

        await _speakSafely(microphoneDeniedMessage, wait: false);
        return;
      }

      await _speakSafely(permissionGrantedAnnouncement, wait: true);
    } else {
      await _speakSafely(readyAnnouncement, wait: true);
    }

    await _runListenLoop();
  }

  /// Cancels any active listening without announcements, for modes that
  /// take over the microphone (guitar recording, Play Along).
  Future<void> suspendForMicrophoneHandoff(String status) async {
    _suspendRequested = true;

    await _voiceService.cancel();

    _setState(VoiceControlState.paused, status);
  }

  /// Called when the app moves to the background.
  Future<void> handleAppBackgrounded() async {
    if (!isSessionActive) {
      return;
    }

    _suspendRequested = true;

    await _voiceService.cancel();
    await _speechService.stop();

    _setState(VoiceControlState.paused, 'Voice control is paused.');
  }

  Future<void> _runListenLoop() async {
    _consecutiveFailures = 0;

    while (!_disposed) {
      _suspendRequested = false;

      _setState(VoiceControlState.listening, 'Listening for a command.');

      await HapticFeedback.mediumImpact();

      final String? phrase;

      try {
        phrase = await _voiceService.listen();
      } on VoiceCommandException catch (error) {
        final keepListening = await _handleListenError(error);

        if (!keepListening) {
          return;
        }

        continue;
      }

      if (_disposed) {
        return;
      }

      if (phrase == null) {
        // Listening was cancelled.
        if (!_suspendRequested) {
          _setState(VoiceControlState.paused, 'Voice control stopped.');
        }

        return;
      }

      _consecutiveFailures = 0;

      _setState(VoiceControlState.processing, 'Heard: $phrase');

      await HapticFeedback.selectionClick();

      final outcome = await _onPhrase(phrase);

      if (_disposed) {
        return;
      }

      switch (outcome) {
        case VoiceFlowOutcome.continueListening:
          continue;

        case VoiceFlowOutcome.suspendListening:
          if (isSessionActive) {
            _setState(VoiceControlState.paused, _statusMessage);
          }

          return;

        case VoiceFlowOutcome.stopListening:
          _setState(VoiceControlState.paused, 'Voice control stopped.');
          return;
      }
    }
  }

  /// Returns whether the listen loop should continue.
  Future<bool> _handleListenError(VoiceCommandException error) async {
    if (_disposed) {
      return false;
    }

    if (_suspendRequested) {
      // The session was suspended externally while listening; the
      // suspension already set the state.
      return false;
    }

    if (error.isTimeout) {
      _setState(
        VoiceControlState.paused,
        'No command was heard. Voice control is paused.',
      );

      await _speakSafely(
        'I did not hear a command. Voice control is paused.',
        wait: false,
      );

      return false;
    }

    if (error.isNoMatch) {
      _consecutiveFailures += 1;

      if (_consecutiveFailures >= 2) {
        _setState(
          VoiceControlState.paused,
          'Commands were not understood. Voice control is paused.',
        );

        await _speakSafely(
          'I did not understand that command. Voice control is paused.',
          wait: false,
        );

        return false;
      }

      await _speakSafely(
        'I did not understand that command. Please try again.',
        wait: true,
      );

      return true;
    }

    if (error.isPermissionDenied) {
      _setState(
        VoiceControlState.unavailable,
        'Microphone access was not granted. '
        'Voice control is unavailable.',
      );

      await _speakSafely(microphoneDeniedMessage, wait: false);

      return false;
    }

    if (error.isUnavailable) {
      _setState(VoiceControlState.unavailable, error.message);
      return false;
    }

    _setState(VoiceControlState.paused, error.message);

    await _speakSafely(error.message, wait: false);

    return false;
  }

  Future<void> _speakSafely(String text, {required bool wait}) async {
    try {
      if (wait) {
        await _speechService.speakAndWait(text);
      } else {
        await _speechService.speak(text);
      }
    } on SpeechException {
      // TTS failure must not break the session; the visual status and
      // screen-reader semantics still carry the message.
    }
  }

  void _setState(VoiceControlState state, String statusMessage) {
    if (_disposed) {
      return;
    }

    _state = state;
    _statusMessage = statusMessage;

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    _voiceService.cancel();

    super.dispose();
  }
}
