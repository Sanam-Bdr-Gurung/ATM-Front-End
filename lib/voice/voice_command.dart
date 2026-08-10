/// The typed, deterministic command vocabulary of ChordAssist.
///
/// Recognized speech is parsed into one of these commands; state-aware
/// handling decides what a command means in the current app state.
enum VoiceCommand {
  help,

  chooseFile,
  analyzeAudio,

  startRecording,
  analyzeRecording,
  recordAgain,
  stopRecording,

  readResult,
  repeatResult,

  showDetails,
  hideDetails,

  retryConnection,

  playAlong,
  pausePlayback,
  resumePlayback,
  stopPlayback,

  stopListening,

  unknown,
}
