import 'package:flutter/services.dart';

class SpeechException implements Exception {
  const SpeechException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class SpeechService {
  const SpeechService();

  static const MethodChannel _channel = MethodChannel('chordassist/tts');

  /// Starts speaking and returns as soon as Android accepts the text.
  Future<void> speak(String text) async {
    final message = text.trim();

    if (message.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('speak', <String, Object>{
        'text': message,
      });
    } on PlatformException catch (error) {
      throw SpeechException(error.message ?? 'Text-to-speech is unavailable.');
    } on MissingPluginException {
      throw const SpeechException('Text-to-speech is unavailable.');
    }
  }

  /// Speaks and completes only after the utterance has audibly finished.
  ///
  /// This is the half-duplex building block: voice recognition must not
  /// start until this future resolves.
  Future<void> speakAndWait(String text) async {
    final message = text.trim();

    if (message.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('speakAndWait', <String, Object>{
        'text': message,
      });
    } on PlatformException catch (error) {
      throw SpeechException(error.message ?? 'Text-to-speech is unavailable.');
    } on MissingPluginException {
      throw const SpeechException('Text-to-speech is unavailable.');
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Stopping speech is best-effort.
    } on MissingPluginException {
      // Speech is unavailable, so there is nothing to stop.
    }
  }
}
