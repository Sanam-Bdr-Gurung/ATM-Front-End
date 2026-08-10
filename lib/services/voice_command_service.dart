import 'package:flutter/services.dart';

/// Stable error codes reported by the native voice recognition channel.
class VoiceErrorCode {
  const VoiceErrorCode._();

  static const String noMatch = 'NO_MATCH';
  static const String timeout = 'TIMEOUT';
  static const String permissionDenied = 'PERMISSION_DENIED';
  static const String busy = 'BUSY';
  static const String network = 'NETWORK';
  static const String unavailable = 'UNAVAILABLE';
}

class VoiceCommandException implements Exception {
  const VoiceCommandException(this.message, {this.code = ''});

  final String message;

  final String code;

  bool get isNoMatch => code == VoiceErrorCode.noMatch;

  bool get isTimeout => code == VoiceErrorCode.timeout;

  bool get isPermissionDenied => code == VoiceErrorCode.permissionDenied;

  bool get isUnavailable => code == VoiceErrorCode.unavailable;

  @override
  String toString() {
    return message;
  }
}

class VoiceCommandService {
  const VoiceCommandService();

  static const MethodChannel _channel = MethodChannel('chordassist/voice');

  Future<bool> hasMicrophonePermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermission');

      return granted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      throw const VoiceCommandException(
        'Voice control is unavailable on this device.',
        code: VoiceErrorCode.unavailable,
      );
    }
  }

  /// Shows the Android microphone permission dialog and resolves with
  /// whether permission was granted.
  Future<bool> requestMicrophonePermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');

      return granted ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      throw const VoiceCommandException(
        'Voice control is unavailable on this device.',
        code: VoiceErrorCode.unavailable,
      );
    }
  }

  /// Runs one bounded speech-recognition request.
  ///
  /// Resolves with the recognized phrase, or null when listening was
  /// cancelled. Throws [VoiceCommandException] with a stable [VoiceErrorCode]
  /// for recognition failures.
  Future<String?> listen() async {
    try {
      final result = await _channel.invokeMethod<String>('listen');

      final phrase = result?.trim();

      if (phrase == null || phrase.isEmpty) {
        return null;
      }

      return phrase;
    } on PlatformException catch (error) {
      throw VoiceCommandException(
        error.message ?? 'Voice recognition is unavailable.',
        code: error.code,
      );
    } on MissingPluginException {
      throw const VoiceCommandException(
        'Voice control is unavailable on this device.',
        code: VoiceErrorCode.unavailable,
      );
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Cancellation is best-effort.
    } on MissingPluginException {
      // Voice control is unavailable, so there is nothing to cancel.
    }
  }
}
