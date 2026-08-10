import 'package:chords_finder/voice/voice_command.dart';
import 'package:chords_finder/voice/voice_command_responder.dart';
import 'package:flutter_test/flutter_test.dart';

VoiceAppSnapshot snapshot({
  bool serviceReady = true,
  bool hasSelectedAudio = false,
  bool isAnalyzing = false,
  bool hasResult = false,
  bool detailsVisible = false,
  bool selectedAudioIsRecording = false,
  bool playAlongActive = false,
  bool playAlongPaused = false,
}) {
  return VoiceAppSnapshot(
    serviceReady: serviceReady,
    hasSelectedAudio: hasSelectedAudio,
    isAnalyzing: isAnalyzing,
    hasResult: hasResult,
    detailsVisible: detailsVisible,
    selectedAudioIsRecording: selectedAudioIsRecording,
    playAlongActive: playAlongActive,
    playAlongPaused: playAlongPaused,
  );
}

void main() {
  const responder = VoiceCommandResponder();

  group('VoiceCommandResponder', () {
    test('help is always accepted', () {
      final decision = responder.decide(VoiceCommand.help, snapshot());

      expect(decision.action, VoiceAction.help);
    });

    test('analyze with nothing selected explains what to do', () {
      final decision = responder.decide(
        VoiceCommand.analyzeAudio,
        snapshot(hasSelectedAudio: false),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('No audio is selected'));
      expect(decision.speech, contains('choose file'));
    });

    test('analyze while backend is offline points to retry', () {
      final decision = responder.decide(
        VoiceCommand.analyzeAudio,
        snapshot(hasSelectedAudio: true, serviceReady: false),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('retry connection'));
    });

    test('analyze during analysis asks the user to wait', () {
      final decision = responder.decide(
        VoiceCommand.analyzeAudio,
        snapshot(hasSelectedAudio: true, isAnalyzing: true),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('currently analyzing'));
    });

    test('analyze with valid audio and ready service is accepted', () {
      final decision = responder.decide(
        VoiceCommand.analyzeAudio,
        snapshot(hasSelectedAudio: true),
      );

      expect(decision.action, VoiceAction.analyzeSelectedAudio);
      expect(decision.speech, contains('Basic Pitch'));
    });

    test('analyzing a recording announces the recording wording', () {
      final decision = responder.decide(
        VoiceCommand.analyzeRecording,
        snapshot(hasSelectedAudio: true, selectedAudioIsRecording: true),
      );

      expect(decision.action, VoiceAction.analyzeSelectedAudio);
      expect(decision.speech, contains('your recording'));
    });

    test('read result before analysis is rejected with guidance', () {
      final decision = responder.decide(
        VoiceCommand.readResult,
        snapshot(hasResult: false),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('No analysis result'));
    });

    test('read result with a result is accepted', () {
      final decision = responder.decide(
        VoiceCommand.readResult,
        snapshot(hasResult: true),
      );

      expect(decision.action, VoiceAction.readResult);
    });

    test('details commands respect visibility state', () {
      expect(
        responder
            .decide(
              VoiceCommand.showDetails,
              snapshot(hasResult: true, detailsVisible: false),
            )
            .action,
        VoiceAction.showDetails,
      );

      expect(
        responder
            .decide(
              VoiceCommand.showDetails,
              snapshot(hasResult: true, detailsVisible: true),
            )
            .isRejection,
        isTrue,
      );

      expect(
        responder
            .decide(
              VoiceCommand.hideDetails,
              snapshot(hasResult: true, detailsVisible: true),
            )
            .action,
        VoiceAction.hideDetails,
      );

      expect(
        responder
            .decide(
              VoiceCommand.hideDetails,
              snapshot(hasResult: true, detailsVisible: false),
            )
            .isRejection,
        isTrue,
      );
    });

    test('details commands without a result are rejected', () {
      expect(
        responder
            .decide(VoiceCommand.showDetails, snapshot(hasResult: false))
            .isRejection,
        isTrue,
      );
    });

    test('start recording is accepted when idle', () {
      final decision = responder.decide(
        VoiceCommand.startRecording,
        snapshot(),
      );

      expect(decision.action, VoiceAction.startRecording);
    });

    test('record again maps to the same recording action', () {
      final decision = responder.decide(VoiceCommand.recordAgain, snapshot());

      expect(decision.action, VoiceAction.startRecording);
    });

    test('start recording during analysis is rejected', () {
      final decision = responder.decide(
        VoiceCommand.startRecording,
        snapshot(isAnalyzing: true),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('currently analyzing'));
    });

    test('stop recording outside recording mode explains state', () {
      final decision = responder.decide(VoiceCommand.stopRecording, snapshot());

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('No recording is in progress'));
    });

    test('play along before analysis explains the requirement', () {
      final decision = responder.decide(
        VoiceCommand.playAlong,
        snapshot(hasResult: false),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('after an audio file'));
    });

    test('play along with a result is accepted', () {
      final decision = responder.decide(
        VoiceCommand.playAlong,
        snapshot(hasResult: true, hasSelectedAudio: true),
      );

      expect(decision.action, VoiceAction.playAlong);
    });

    test('play along while already running is rejected', () {
      final decision = responder.decide(
        VoiceCommand.playAlong,
        snapshot(hasResult: true, playAlongActive: true),
      );

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('already running'));
    });

    test('pause is accepted only while playing', () {
      expect(
        responder
            .decide(
              VoiceCommand.pausePlayback,
              snapshot(hasResult: true, playAlongActive: true),
            )
            .action,
        VoiceAction.pausePlayback,
      );

      expect(
        responder.decide(VoiceCommand.pausePlayback, snapshot()).isRejection,
        isTrue,
      );
    });

    test('resume is accepted only while paused', () {
      expect(
        responder
            .decide(
              VoiceCommand.resumePlayback,
              snapshot(
                hasResult: true,
                playAlongActive: true,
                playAlongPaused: true,
              ),
            )
            .action,
        VoiceAction.resumePlayback,
      );

      expect(
        responder.decide(VoiceCommand.resumePlayback, snapshot()).isRejection,
        isTrue,
      );
    });

    test('stop during Play Along stops playback', () {
      final decision = responder.decide(
        VoiceCommand.stopPlayback,
        snapshot(hasResult: true, playAlongActive: true, playAlongPaused: true),
      );

      expect(decision.action, VoiceAction.stopPlayback);
    });

    test('stop with no playback stops listening', () {
      final decision = responder.decide(VoiceCommand.stopPlayback, snapshot());

      expect(decision.action, VoiceAction.stopListening);
    });

    test('stop listening is always accepted', () {
      final decision = responder.decide(VoiceCommand.stopListening, snapshot());

      expect(decision.action, VoiceAction.stopListening);
    });

    test('unknown command produces spoken guidance', () {
      final decision = responder.decide(VoiceCommand.unknown, snapshot());

      expect(decision.isRejection, isTrue);
      expect(decision.speech, contains('help'));
    });
  });
}
