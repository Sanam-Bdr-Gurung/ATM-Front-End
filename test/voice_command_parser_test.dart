import 'package:chords_finder/voice/voice_command.dart';
import 'package:chords_finder/voice/voice_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = VoiceCommandParser();

  group('VoiceCommandParser.normalize', () {
    test('lowercases, strips punctuation, and collapses spaces', () {
      expect(
        VoiceCommandParser.normalize('  Analyze,   Audio!  '),
        'analyze audio',
      );
    });

    test('removes leading and trailing please', () {
      expect(
        VoiceCommandParser.normalize('Please analyze audio'),
        'analyze audio',
      );

      expect(
        VoiceCommandParser.normalize('analyze audio, please'),
        'analyze audio',
      );
    });
  });

  group('VoiceCommandParser.parse', () {
    VoiceCommand parse(String phrase) => parser.parse(phrase);

    test('handoff acceptance examples', () {
      expect(parse('analyse audio'), VoiceCommand.analyzeAudio);
      expect(parse('select audio'), VoiceCommand.chooseFile);
      expect(parse('play a long'), VoiceCommand.playAlong);
      expect(parse('record guitar'), VoiceCommand.startRecording);
    });

    test('help variants', () {
      for (final phrase in [
        'help',
        'what can I say',
        'commands',
        'voice commands',
      ]) {
        expect(parse(phrase), VoiceCommand.help, reason: phrase);
      }
    });

    test('choose file variants', () {
      for (final phrase in [
        'choose file',
        'select file',
        'choose audio',
        'select audio',
        'open audio',
        'pick a file',
      ]) {
        expect(parse(phrase), VoiceCommand.chooseFile, reason: phrase);
      }
    });

    test('analysis variants including British spelling', () {
      for (final phrase in [
        'analyze',
        'analyse',
        'analyze audio',
        'analyse audio',
        'analyze file',
        'recognize chords',
        'find chords',
      ]) {
        expect(parse(phrase), VoiceCommand.analyzeAudio, reason: phrase);
      }
    });

    test('analyze recording is distinct from analyze audio', () {
      for (final phrase in [
        'analyze recording',
        'analyse recording',
        'analyze my recording',
      ]) {
        expect(parse(phrase), VoiceCommand.analyzeRecording, reason: phrase);
      }
    });

    test('result variants', () {
      for (final phrase in [
        'read result',
        'read results',
        'say the chords',
        'what are the chords',
      ]) {
        expect(parse(phrase), VoiceCommand.readResult, reason: phrase);
      }

      for (final phrase in ['repeat result', 'repeat', 'say that again']) {
        expect(parse(phrase), VoiceCommand.repeatResult, reason: phrase);
      }
    });

    test('detail variants', () {
      for (final phrase in [
        'show details',
        'show segment details',
        'segment details',
      ]) {
        expect(parse(phrase), VoiceCommand.showDetails, reason: phrase);
      }

      for (final phrase in ['hide details', 'hide segment details']) {
        expect(parse(phrase), VoiceCommand.hideDetails, reason: phrase);
      }
    });

    test('recording variants including recognizer mistakes', () {
      for (final phrase in [
        'start recording',
        'record guitar',
        'record audio',
        'record',
        'start record',
      ]) {
        expect(parse(phrase), VoiceCommand.startRecording, reason: phrase);
      }

      expect(parse('record again'), VoiceCommand.recordAgain);
      expect(parse('stop recording'), VoiceCommand.stopRecording);
    });

    test('play along variants including recognizer mistakes', () {
      for (final phrase in [
        'play along',
        'play a long',
        'start play along',
        'play the analysis',
        'play with chords',
      ]) {
        expect(parse(phrase), VoiceCommand.playAlong, reason: phrase);
      }
    });

    test('playback control variants', () {
      expect(parse('pause'), VoiceCommand.pausePlayback);
      expect(parse('pause playback'), VoiceCommand.pausePlayback);

      expect(parse('resume'), VoiceCommand.resumePlayback);
      expect(parse('continue'), VoiceCommand.resumePlayback);
      expect(parse('resume playback'), VoiceCommand.resumePlayback);

      expect(parse('stop'), VoiceCommand.stopPlayback);
      expect(parse('stop playback'), VoiceCommand.stopPlayback);
      expect(parse('stop play along'), VoiceCommand.stopPlayback);
    });

    test('connection variants', () {
      for (final phrase in ['retry', 'retry connection', 'check connection']) {
        expect(parse(phrase), VoiceCommand.retryConnection, reason: phrase);
      }
    });

    test('voice control variants', () {
      for (final phrase in ['stop listening', 'end voice control']) {
        expect(parse(phrase), VoiceCommand.stopListening, reason: phrase);
      }
    });

    test('punctuation and casing do not change the command', () {
      expect(parse('Analyze Audio.'), VoiceCommand.analyzeAudio);
      expect(parse('PLAY ALONG!'), VoiceCommand.playAlong);
      expect(parse('  Stop   Listening '), VoiceCommand.stopListening);
    });

    test('unrelated speech maps to unknown', () {
      for (final phrase in [
        '',
        '   ',
        'what is the weather today',
        'open settings',
        'guitar',
        'analyze audio now immediately',
      ]) {
        expect(parse(phrase), VoiceCommand.unknown, reason: phrase);
      }
    });
  });
}
