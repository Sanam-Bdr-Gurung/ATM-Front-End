import 'voice_command.dart';

/// Deterministic mapping from recognized speech to [VoiceCommand]s.
///
/// No machine learning and no fuzzy matching: phrases are normalized
/// (lowercase, punctuation stripped, whitespace collapsed, polite
/// filler removed) and looked up in a fixed synonym table that includes
/// common speech-recognition variants such as "play a long".
class VoiceCommandParser {
  const VoiceCommandParser();

  VoiceCommand parse(String rawPhrase) {
    final phrase = normalize(rawPhrase);

    if (phrase.isEmpty) {
      return VoiceCommand.unknown;
    }

    return _phraseTable[phrase] ?? VoiceCommand.unknown;
  }

  /// Lowercases, strips punctuation, collapses whitespace, and removes
  /// leading/trailing "please".
  static String normalize(String raw) {
    var phrase = raw
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (phrase.startsWith('please ')) {
      phrase = phrase.substring('please '.length);
    }

    if (phrase.endsWith(' please')) {
      phrase = phrase.substring(0, phrase.length - ' please'.length);
    }

    return phrase.trim();
  }

  static const Map<String, VoiceCommand> _phraseTable = {
    // Help
    'help': VoiceCommand.help,
    'what can i say': VoiceCommand.help,
    'commands': VoiceCommand.help,
    'voice commands': VoiceCommand.help,
    'list commands': VoiceCommand.help,
    'show commands': VoiceCommand.help,

    // Choose an existing file
    'choose file': VoiceCommand.chooseFile,
    'choose a file': VoiceCommand.chooseFile,
    'select file': VoiceCommand.chooseFile,
    'select a file': VoiceCommand.chooseFile,
    'choose audio': VoiceCommand.chooseFile,
    'select audio': VoiceCommand.chooseFile,
    'open audio': VoiceCommand.chooseFile,
    'open file': VoiceCommand.chooseFile,
    'pick file': VoiceCommand.chooseFile,
    'pick a file': VoiceCommand.chooseFile,
    'choose wav file': VoiceCommand.chooseFile,

    // Analysis
    'analyze': VoiceCommand.analyzeAudio,
    'analyse': VoiceCommand.analyzeAudio,
    'analyze audio': VoiceCommand.analyzeAudio,
    'analyse audio': VoiceCommand.analyzeAudio,
    'analyze file': VoiceCommand.analyzeAudio,
    'analyse file': VoiceCommand.analyzeAudio,
    'analyze the audio': VoiceCommand.analyzeAudio,
    'analyse the audio': VoiceCommand.analyzeAudio,
    'recognize chords': VoiceCommand.analyzeAudio,
    'recognise chords': VoiceCommand.analyzeAudio,
    'find chords': VoiceCommand.analyzeAudio,
    'find the chords': VoiceCommand.analyzeAudio,

    // Analysis of a phone recording
    'analyze recording': VoiceCommand.analyzeRecording,
    'analyse recording': VoiceCommand.analyzeRecording,
    'analyze the recording': VoiceCommand.analyzeRecording,
    'analyse the recording': VoiceCommand.analyzeRecording,
    'analyze my recording': VoiceCommand.analyzeRecording,
    'analyse my recording': VoiceCommand.analyzeRecording,

    // Result speech
    'read result': VoiceCommand.readResult,
    'read results': VoiceCommand.readResult,
    'read the result': VoiceCommand.readResult,
    'read the results': VoiceCommand.readResult,
    'read result aloud': VoiceCommand.readResult,
    'say the chords': VoiceCommand.readResult,
    'what are the chords': VoiceCommand.readResult,

    'repeat result': VoiceCommand.repeatResult,
    'repeat results': VoiceCommand.repeatResult,
    'repeat the result': VoiceCommand.repeatResult,
    'repeat that': VoiceCommand.repeatResult,
    'say that again': VoiceCommand.repeatResult,
    'repeat': VoiceCommand.repeatResult,

    // Segment details
    'show details': VoiceCommand.showDetails,
    'show the details': VoiceCommand.showDetails,
    'show segment details': VoiceCommand.showDetails,
    'segment details': VoiceCommand.showDetails,

    'hide details': VoiceCommand.hideDetails,
    'hide the details': VoiceCommand.hideDetails,
    'hide segment details': VoiceCommand.hideDetails,

    // Recording
    'start recording': VoiceCommand.startRecording,
    'start record': VoiceCommand.startRecording,
    'begin recording': VoiceCommand.startRecording,
    'record guitar': VoiceCommand.startRecording,
    'record audio': VoiceCommand.startRecording,
    'record': VoiceCommand.startRecording,
    'record now': VoiceCommand.startRecording,

    'record again': VoiceCommand.recordAgain,
    'rerecord': VoiceCommand.recordAgain,
    're record': VoiceCommand.recordAgain,

    'stop recording': VoiceCommand.stopRecording,
    'stop the recording': VoiceCommand.stopRecording,

    // Play Along
    'play along': VoiceCommand.playAlong,
    'play a long': VoiceCommand.playAlong,
    'playalong': VoiceCommand.playAlong,
    'start play along': VoiceCommand.playAlong,
    'play the analysis': VoiceCommand.playAlong,
    'play with chords': VoiceCommand.playAlong,

    // Playback control
    'pause': VoiceCommand.pausePlayback,
    'pause playback': VoiceCommand.pausePlayback,
    'pause play along': VoiceCommand.pausePlayback,

    'resume': VoiceCommand.resumePlayback,
    'continue': VoiceCommand.resumePlayback,
    'resume playback': VoiceCommand.resumePlayback,
    'continue playback': VoiceCommand.resumePlayback,
    'resume play along': VoiceCommand.resumePlayback,
    'continue play along': VoiceCommand.resumePlayback,

    'stop': VoiceCommand.stopPlayback,
    'stop playback': VoiceCommand.stopPlayback,
    'stop play along': VoiceCommand.stopPlayback,

    // Connection
    'retry': VoiceCommand.retryConnection,
    'retry connection': VoiceCommand.retryConnection,
    'check connection': VoiceCommand.retryConnection,
    'reconnect': VoiceCommand.retryConnection,
    'try again': VoiceCommand.retryConnection,

    // Voice control
    'stop listening': VoiceCommand.stopListening,
    'end voice control': VoiceCommand.stopListening,
    'stop voice control': VoiceCommand.stopListening,
    'stop voice': VoiceCommand.stopListening,
  };
}
