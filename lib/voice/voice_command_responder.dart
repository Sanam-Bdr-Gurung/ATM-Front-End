import 'voice_command.dart';

/// A snapshot of the application state that command handling needs.
///
/// Kept as plain booleans so the decision logic stays pure and
/// unit-testable without widgets or platform channels.
class VoiceAppSnapshot {
  const VoiceAppSnapshot({
    required this.serviceReady,
    required this.hasSelectedAudio,
    required this.isAnalyzing,
    required this.hasResult,
    required this.detailsVisible,
  });

  final bool serviceReady;

  final bool hasSelectedAudio;

  final bool isAnalyzing;

  final bool hasResult;

  final bool detailsVisible;
}

/// The application action a decided command should invoke. Every action
/// maps onto the same function the equivalent on-screen button calls.
enum VoiceAction {
  /// No action: [VoiceDecision.speech] carries spoken guidance instead.
  none,

  help,
  chooseFile,
  startRecording,
  analyzeSelectedAudio,
  readResult,
  showDetails,
  hideDetails,
  retryConnection,
  stopListening,
}

class VoiceDecision {
  const VoiceDecision.reject(String this.speech) : action = VoiceAction.none;

  const VoiceDecision.accept(this.action, {this.speech});

  /// The action to run, or [VoiceAction.none] for guidance-only replies.
  final VoiceAction action;

  /// What to say: rejection guidance, or an announcement to speak
  /// before the accepted action runs.
  final String? speech;

  bool get isRejection => action == VoiceAction.none;
}

/// Decides what a recognized command means in the current app state.
///
/// Every rejection is worded so it makes sense without seeing the
/// screen, following the accessibility handoff requirements.
class VoiceCommandResponder {
  const VoiceCommandResponder();

  static const String helpSpeech =
      'You can say: choose file, start recording, analyze audio, '
      'read result, show details, hide details, retry connection, '
      'or stop listening.';

  static const String _analysisInProgress =
      'ChordAssist is currently analyzing audio. '
      'Please wait for analysis to finish.';

  static const String _noResultYet =
      'No analysis result is available yet. '
      'Say analyze audio after choosing or recording audio.';

  VoiceDecision decide(VoiceCommand command, VoiceAppSnapshot state) {
    switch (command) {
      case VoiceCommand.help:
        return const VoiceDecision.accept(VoiceAction.help);

      case VoiceCommand.chooseFile:
        if (state.isAnalyzing) {
          return const VoiceDecision.reject(_analysisInProgress);
        }

        return const VoiceDecision.accept(
          VoiceAction.chooseFile,
          speech: 'Opening the audio file picker.',
        );

      case VoiceCommand.analyzeAudio:
      case VoiceCommand.analyzeRecording:
        if (state.isAnalyzing) {
          return const VoiceDecision.reject(_analysisInProgress);
        }

        if (!state.hasSelectedAudio) {
          return const VoiceDecision.reject(
            'No audio is selected. '
            'Say choose file or start recording.',
          );
        }

        if (!state.serviceReady) {
          return const VoiceDecision.reject(
            'The analysis service is unavailable. '
            'Say retry connection to try again.',
          );
        }

        return const VoiceDecision.accept(
          VoiceAction.analyzeSelectedAudio,
          speech: 'Analyzing the audio using Basic Pitch.',
        );

      case VoiceCommand.readResult:
      case VoiceCommand.repeatResult:
        if (state.isAnalyzing) {
          return const VoiceDecision.reject(_analysisInProgress);
        }

        if (!state.hasResult) {
          return const VoiceDecision.reject(_noResultYet);
        }

        return const VoiceDecision.accept(VoiceAction.readResult);

      case VoiceCommand.showDetails:
        if (!state.hasResult) {
          return const VoiceDecision.reject(_noResultYet);
        }

        if (state.detailsVisible) {
          return const VoiceDecision.reject(
            'Segment details are already shown.',
          );
        }

        return const VoiceDecision.accept(
          VoiceAction.showDetails,
          speech: 'Showing segment details.',
        );

      case VoiceCommand.hideDetails:
        if (!state.hasResult) {
          return const VoiceDecision.reject(_noResultYet);
        }

        if (!state.detailsVisible) {
          return const VoiceDecision.reject(
            'Segment details are already hidden.',
          );
        }

        return const VoiceDecision.accept(
          VoiceAction.hideDetails,
          speech: 'Segment details hidden.',
        );

      case VoiceCommand.retryConnection:
        if (state.isAnalyzing) {
          return const VoiceDecision.reject(_analysisInProgress);
        }

        return const VoiceDecision.accept(
          VoiceAction.retryConnection,
          speech: 'Checking the analysis service.',
        );

      case VoiceCommand.startRecording:
      case VoiceCommand.recordAgain:
        if (state.isAnalyzing) {
          return const VoiceDecision.reject(_analysisInProgress);
        }

        // The recording flow speaks its own detailed instructions
        // before the microphone switches to the guitar.
        return const VoiceDecision.accept(VoiceAction.startRecording);

      case VoiceCommand.stopRecording:
        // While actually recording, the voice recognizer is off, so
        // this command can only arrive outside recording mode.
        return const VoiceDecision.reject(
          'No recording is in progress. '
          'Say start recording to record your guitar.',
        );

      // Play Along arrives in a later checkpoint.
      case VoiceCommand.playAlong:
        if (!state.hasResult) {
          return const VoiceDecision.reject(
            'Play Along is available after an audio file '
            'has been analyzed.',
          );
        }

        return const VoiceDecision.reject(
          'Play Along is not available yet in this version.',
        );

      case VoiceCommand.pausePlayback:
      case VoiceCommand.resumePlayback:
        return const VoiceDecision.reject('Nothing is playing.');

      case VoiceCommand.stopPlayback:
        // With no playback running, "stop" means stop voice control.
        return const VoiceDecision.accept(VoiceAction.stopListening);

      case VoiceCommand.stopListening:
        return const VoiceDecision.accept(VoiceAction.stopListening);

      case VoiceCommand.unknown:
        return const VoiceDecision.reject(
          'I did not understand that command. '
          'Say help to hear available commands.',
        );
    }
  }
}
