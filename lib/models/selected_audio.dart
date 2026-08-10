import 'package:file_selector/file_selector.dart';

enum AudioSourceType { pickedFile, recording }

/// The audio ChordAssist will analyze, regardless of whether it came
/// from the document picker or the phone microphone. Analysis and
/// playback never care about the difference.
class SelectedAudio {
  const SelectedAudio({
    required this.file,
    required this.sizeBytes,
    required this.source,
    this.duration,
  });

  final XFile file;

  final int sizeBytes;

  final AudioSourceType source;

  /// Known length of the audio, currently only for recordings.
  final Duration? duration;

  String get name => file.name;

  bool get isRecording => source == AudioSourceType.recording;

  /// Human-facing description used in the status card and speech.
  String get displayName {
    if (isRecording) {
      return 'Guitar recording';
    }

    return name;
  }
}
