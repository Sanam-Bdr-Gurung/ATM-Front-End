import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../playalong/playalong_controller.dart';
import '../recording/recording_controller.dart';
import '../services/chord_api_service.dart';
import '../models/chord_analysis.dart';
import '../models/selected_audio.dart';
import '../services/playback_service.dart';
import '../services/recording_service.dart';
import '../services/speech_service.dart';

import '../services/voice_command_service.dart';
import 'recording_screen.dart';
import '../voice/voice_command.dart';
import '../voice/voice_command_controller.dart';
import '../voice/voice_command_parser.dart';
import '../voice/voice_command_responder.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.apiService = const ChordApiService(),
    this.speechService = const SpeechService(),
    this.voiceCommandService = const VoiceCommandService(),
    this.recordingService,
    this.playbackService,
    this.autoStartVoiceControl = true,
  });

  final ChordApiService apiService;
  final SpeechService speechService;
  final VoiceCommandService voiceCommandService;

  /// Injectable for tests; the real recorder is created when omitted.
  final RecordingService? recordingService;

  /// Injectable for tests; the real player is created when omitted.
  final PlaybackService? playbackService;

  /// Whether a voice session starts automatically on launch, so the
  /// app is usable without touching the screen. Tests may disable it.
  final bool autoStartVoiceControl;

  @override
  State<HomeScreen> createState() {
    return _HomeScreenState();
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  SelectedAudio? _selectedAudio;

  String? _selectionError;

  bool _isPickingFile = false;
  late final ChordApiService _apiService;

  late final SpeechService _speechService;

  bool _isCheckingService = true;

  bool _serviceReady = false;

  String _serviceStatus = 'Checking analysis service.';
  bool _isAnalyzing = false;

  ChordAnalysisResult? _analysisResult;
  String? _analysisError;

  bool _showSegmentDetails = false;

  bool get _hasValidSelection {
    return _selectedAudio != null && _selectionError == null;
  }

  late final VoiceCommandController _voiceController;

  late final RecordingService _recordingService;

  bool _isRecordingFlowActive = false;

  late final PlayAlongController _playAlongController;

  /// Whether a voice session should resume once Play Along releases
  /// the audio path (set when a session was active at start).
  bool _resumeVoiceAfterPlayAlong = false;

  @override
  void initState() {
    super.initState();

    _apiService = widget.apiService;
    _speechService = widget.speechService;

    _recordingService = widget.recordingService ?? RecordingService();

    _playAlongController = PlayAlongController(
      playback: widget.playbackService ?? PlaybackService(),
      speech: widget.speechService,
    );

    _playAlongController.onFinished = _handlePlayAlongFinished;

    _voiceController = VoiceCommandController(
      speechService: widget.speechService,
      voiceService: widget.voiceCommandService,
      onPhrase: _handleVoicePhrase,
    );

    WidgetsBinding.instance.addObserver(this);

    _checkAnalysisService();

    if (widget.autoStartVoiceControl) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _voiceController.startLaunchSession();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _voiceController.dispose();
    _playAlongController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _voiceController.handleAppBackgrounded();
    }
  }

  static const VoiceCommandParser _voiceParser = VoiceCommandParser();

  static const VoiceCommandResponder _voiceResponder = VoiceCommandResponder();

  int _consecutiveUnknownCommands = 0;

  VoiceAppSnapshot get _voiceSnapshot {
    return VoiceAppSnapshot(
      serviceReady: _serviceReady,
      hasSelectedAudio: _hasValidSelection,
      isAnalyzing: _isAnalyzing,
      hasResult: _analysisResult != null,
      detailsVisible: _showSegmentDetails,
      selectedAudioIsRecording: _selectedAudio?.isRecording ?? false,
      playAlongActive: _playAlongController.isActive,
      playAlongPaused: _playAlongController.isPaused,
    );
  }

  /// Starts Play Along and hands the audio path over to playback,
  /// suspending any voice session first. Returns an error message, or
  /// null on success.
  Future<String?> _startPlayAlong() async {
    final result = _analysisResult;
    final audio = _selectedAudio;

    if (result == null || audio == null) {
      return 'No analysis result is available yet.';
    }

    await _voiceController.suspendForMicrophoneHandoff('Playing along.');

    await _speakForVoiceFlow(
      'Starting Play Along. '
      'Chord names are announced as the audio plays. '
      'Use the on-screen controls to pause or stop.',
    );

    try {
      unawaited(HapticFeedback.mediumImpact());

      await _playAlongController.start(
        audioPath: audio.file.path,
        segments: result.segments,
      );

      return null;
    } on PlaybackException catch (error) {
      return error.message;
    }
  }

  Future<void> _startPlayAlongFromButton() async {
    final wasVoiceActive = _voiceController.isSessionActive;

    final error = await _startPlayAlong();

    if (error != null) {
      await _speakForVoiceFlow(error);
      return;
    }

    _resumeVoiceAfterPlayAlong = wasVoiceActive;
  }

  Future<void> _pausePlayAlong() async {
    if (!_playAlongController.isPlaying) {
      return;
    }

    await _playAlongController.pause();

    unawaited(HapticFeedback.selectionClick());

    // With playback paused the microphone is free again, so the voice
    // session can take pause/resume/stop commands.
    if (_resumeVoiceAfterPlayAlong && mounted) {
      _voiceController.startManualSession(
        announcement:
            'Play Along paused. '
            'Say resume to continue, or stop playback to finish.',
      );
    } else {
      await _speakForVoiceFlow('Play Along paused.');
    }
  }

  Future<void> _resumePlayAlong() async {
    if (!_playAlongController.isPaused) {
      return;
    }

    await _voiceController.suspendForMicrophoneHandoff('Playing along.');

    await _playAlongController.resume();

    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _stopPlayAlongFromButton() async {
    if (!_playAlongController.isActive) {
      return;
    }

    await _playAlongController.stop();

    unawaited(HapticFeedback.mediumImpact());

    await _speakForVoiceFlow('Play Along stopped.');

    if (_resumeVoiceAfterPlayAlong && mounted) {
      _resumeVoiceAfterPlayAlong = false;

      _voiceController.startManualSession();
    }
  }

  void _handlePlayAlongFinished() {
    HapticFeedback.mediumImpact();

    () async {
      await _speakForVoiceFlow('Play Along finished.');

      if (_resumeVoiceAfterPlayAlong && mounted) {
        _resumeVoiceAfterPlayAlong = false;

        _voiceController.startManualSession();
      }
    }();
  }

  /// Routes a recognized phrase onto the same functions the on-screen
  /// buttons call. Never duplicates application logic.
  Future<VoiceFlowOutcome> _handleVoicePhrase(String phrase) async {
    final command = _voiceParser.parse(phrase);

    final decision = _voiceResponder.decide(command, _voiceSnapshot);

    if (decision.isRejection) {
      if (command == VoiceCommand.unknown) {
        _consecutiveUnknownCommands += 1;
      } else {
        _consecutiveUnknownCommands = 0;
      }

      await _speakForVoiceFlow(decision.speech!);

      if (_consecutiveUnknownCommands >= 3) {
        _consecutiveUnknownCommands = 0;

        await _speakForVoiceFlow('Voice control is paused.');

        return VoiceFlowOutcome.stopListening;
      }

      return VoiceFlowOutcome.continueListening;
    }

    _consecutiveUnknownCommands = 0;

    final announcement = decision.speech;

    if (announcement != null) {
      await _speakForVoiceFlow(announcement);
    }

    return _runVoiceAction(decision.action);
  }

  Future<VoiceFlowOutcome> _runVoiceAction(VoiceAction action) async {
    switch (action) {
      case VoiceAction.none:
        return VoiceFlowOutcome.continueListening;

      case VoiceAction.help:
        await _speakForVoiceFlow(VoiceCommandResponder.helpSpeech);

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.chooseFile:
        final outcome = await _pickWavFile();

        await _speakForVoiceFlow(outcome);

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.startRecording:
        final message = await _runGuitarRecordingFlow();

        await _speakForVoiceFlow(message);

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.analyzeSelectedAudio:
        await _analyzeSelectedAudio();

        await _speakForVoiceFlow(_analysisOutcomeSpeech);

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.readResult:
        final result = _analysisResult;

        if (result != null) {
          await _speakForVoiceFlow(result.speechText);
        }

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.showDetails:
        if (mounted) {
          setState(() {
            _showSegmentDetails = true;
          });
        }

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.hideDetails:
        if (mounted) {
          setState(() {
            _showSegmentDetails = false;
          });
        }

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.retryConnection:
        await _checkAnalysisService();

        await _speakForVoiceFlow(_serviceStatus);

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.playAlong:
        final error = await _startPlayAlong();

        if (error != null) {
          await _speakForVoiceFlow(error);

          return VoiceFlowOutcome.continueListening;
        }

        _resumeVoiceAfterPlayAlong = true;

        return VoiceFlowOutcome.suspendListening;

      case VoiceAction.pausePlayback:
        // Defensive: while audio plays the recognizer is off, so this
        // command normally arrives through the on-screen button.
        await _pausePlayAlong();

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.resumePlayback:
        await _resumePlayAlong();

        _resumeVoiceAfterPlayAlong = true;

        return VoiceFlowOutcome.suspendListening;

      case VoiceAction.stopPlayback:
        await _playAlongController.stop();

        unawaited(HapticFeedback.mediumImpact());

        _resumeVoiceAfterPlayAlong = false;

        await _speakForVoiceFlow('Play Along stopped.');

        return VoiceFlowOutcome.continueListening;

      case VoiceAction.stopListening:
        await _speakForVoiceFlow(
          'Voice control stopped. '
          'Use the Listen for a command button to start again.',
        );

        return VoiceFlowOutcome.stopListening;
    }
  }

  String get _analysisOutcomeSpeech {
    final error = _analysisError;

    if (error != null) {
      return error;
    }

    final result = _analysisResult;

    if (result == null) {
      return 'Audio analysis did not complete. Please try again.';
    }

    return 'Analysis complete. ${result.speechText}';
  }

  /// Speaks within the voice session, waiting for completion so the
  /// recognizer never runs while ChordAssist is talking.
  Future<void> _speakForVoiceFlow(String text) async {
    try {
      await _speechService.speakAndWait(text);
    } on SpeechException {
      // The visual status and semantics still carry the message.
    }
  }

  Future<void> _checkAnalysisService() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isCheckingService = true;
      _serviceReady = false;
      _serviceStatus = 'Checking analysis service.';
    });

    final result = await _apiService.checkHealth();

    if (!mounted) {
      return;
    }

    setState(() {
      _isCheckingService = false;
      _serviceReady = result.ready;
      _serviceStatus = result.message;
    });
  }

  Future<void> _readResultAloud() async {
    final result = _analysisResult;

    if (result == null) {
      return;
    }

    // Half-duplex also applies to touch: reading the result while the
    // recognizer listens would make the app hear its own speech.
    final wasVoiceActive = _voiceController.isSessionActive;

    await _voiceController.suspendForMicrophoneHandoff('Reading result.');

    try {
      await _speechService.speakAndWait(result.speechText);
    } on SpeechException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }

    if (wasVoiceActive && mounted) {
      _voiceController.startManualSession();
    }
  }

  /// Opens the WAV file picker. Returns a spoken outcome message so
  /// the voice flow can announce what happened; the button path
  /// ignores the return value and relies on the visual status card.
  Future<String> _pickWavFile() async {
    if (_isPickingFile) {
      return 'The file picker is already open.';
    }

    setState(() {
      _isPickingFile = true;
      _selectionError = null;
    });

    try {
      const wavTypeGroup = XTypeGroup(
        label: 'WAV audio',
        extensions: <String>['wav'],
      );

      final file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[wavTypeGroup],
      );

      if (!mounted) {
        return 'No file was selected.';
      }

      if (file == null) {
        setState(() {
          _isPickingFile = false;
        });

        return 'No file was selected.';
      }

      final fileName = file.name.trim();

      if (!fileName.toLowerCase().endsWith('.wav')) {
        const message =
            'That file is not a supported WAV file. '
            'Please choose another file.';

        setState(() {
          _selectedAudio = null;
          _selectionError = message;
          _isPickingFile = false;
        });

        return message;
      }

      final fileSize = await file.length();

      if (!mounted) {
        return 'No file was selected.';
      }

      if (fileSize <= 0) {
        const message =
            'The selected WAV file is empty. '
            'Please choose another file.';

        setState(() {
          _selectedAudio = null;
          _selectionError = message;
          _isPickingFile = false;
        });

        return message;
      }

      setState(() {
        _selectedAudio = SelectedAudio(
          file: file,
          sizeBytes: fileSize,
          source: AudioSourceType.pickedFile,
        );
        _selectionError = null;
        _isPickingFile = false;

        _analysisResult = null;
        _analysisError = null;
        _showSegmentDetails = false;
      });

      return 'Selected ${file.name}. '
          'Say analyze audio to continue.';
    } catch (_) {
      const message =
          'The audio file could not be selected. '
          'Please try again.';

      if (!mounted) {
        return message;
      }

      setState(() {
        _selectedAudio = null;
        _selectionError = message;
        _isPickingFile = false;
      });

      return message;
    }
  }

  static const String _preRecordingInstructions =
      'Recording will start now. '
      'While recording, the microphone is used for your guitar, '
      'so voice commands are temporarily unavailable. '
      'The screen is now the Stop recording control. '
      'With TalkBack, touch the screen and double-tap to stop. '
      'Recording will automatically stop after sixty seconds.';

  /// Touch entry point for guitar recording. Suspends any active voice
  /// session first and resumes it after the spoken confirmation.
  Future<void> _recordGuitarFromButton() async {
    final wasVoiceActive = _voiceController.isSessionActive;

    final message = await _runGuitarRecordingFlow();

    await _speakForVoiceFlow(message);

    if (wasVoiceActive && mounted) {
      _voiceController.startManualSession();
    }
  }

  /// The shared recording flow: spoken instructions, microphone
  /// handoff, the dedicated recording screen, and the outcome message.
  /// Voice and touch entry points both run exactly this.
  Future<String> _runGuitarRecordingFlow() async {
    if (_isRecordingFlowActive) {
      return 'Recording is already in progress.';
    }

    _isRecordingFlowActive = true;

    try {
      // The guitar owns the microphone from here until the recording
      // screen closes.
      await _voiceController.suspendForMicrophoneHandoff('Recording guitar.');

      await _speakForVoiceFlow(_preRecordingInstructions);

      if (!mounted) {
        return 'Recording could not start.';
      }

      final outcome = await Navigator.of(context).push<RecordingOutcome>(
        MaterialPageRoute<RecordingOutcome>(
          builder: (_) {
            return RecordingScreen(recordingService: _recordingService);
          },
        ),
      );

      if (outcome == null || outcome.errorMessage != null) {
        return outcome?.errorMessage ??
            'Recording could not start. '
                'Check microphone access and try again.';
      }

      final result = outcome.result!;

      await _handleFinishedRecording(result);

      return _recordingConfirmation(result);
    } finally {
      _isRecordingFlowActive = false;
    }
  }

  /// The finished recording becomes the selected audio, exactly like a
  /// picked file: analysis and playback make no distinction.
  Future<void> _handleFinishedRecording(RecordingResult result) async {
    final file = XFile(result.path);

    int sizeBytes;

    try {
      sizeBytes = await file.length();
    } catch (_) {
      sizeBytes = 0;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedAudio = SelectedAudio(
        file: file,
        sizeBytes: sizeBytes,
        source: AudioSourceType.recording,
        duration: result.duration,
      );
      _selectionError = null;

      _analysisResult = null;
      _analysisError = null;
      _showSegmentDetails = false;
    });
  }

  String _recordingConfirmation(RecordingResult result) {
    final seconds = _speakableSeconds(result.duration);

    final stopPhrase = result.autoStopped
        ? 'Recording stopped automatically.'
        : 'Recording stopped.';

    return '$stopPhrase '
        '$seconds recorded. '
        'Say analyze recording to recognize the chords, '
        'or say record again.';
  }

  String _speakableSeconds(Duration duration) {
    final milliseconds = duration.inMilliseconds;

    if (milliseconds % 1000 == 0) {
      return '${milliseconds ~/ 1000} seconds';
    }

    final seconds = milliseconds / 1000.0;

    return '${seconds.toStringAsFixed(1)} seconds';
  }

  Future<void> _analyzeSelectedAudio() async {
    final audio = _selectedAudio;

    if (audio == null || !_serviceReady || _isAnalyzing) {
      return;
    }
    await _speechService.stop();
    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _analysisError = null;
      _showSegmentDetails = false;
    });

    try {
      final result = await _apiService.analyzeWav(
        fileStream: audio.file.openRead(),
        fileLength: audio.sizeBytes,
        fileName: audio.name,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = false;
        _analysisResult = result;
        _analysisError = null;
      });
    } on ChordApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = false;
        _analysisResult = null;
        _analysisError = error.message;

        if (error.connectionFailure) {
          _serviceReady = false;
          _serviceStatus =
              'Could not connect to the '
              'analysis service.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = false;
        _analysisResult = null;
        _analysisError =
            'Audio analysis failed. '
            'Please try again.';
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes bytes';
    }

    final kilobytes = bytes / 1024;

    if (kilobytes < 1024) {
      return '${kilobytes.toStringAsFixed(1)} KB';
    }

    final megabytes = kilobytes / 1024;

    return '${megabytes.toStringAsFixed(1)} MB';
  }

  String get _selectedAudioMessage {
    final error = _selectionError;

    if (error != null) {
      return error;
    }

    final audio = _selectedAudio;

    if (audio == null) {
      return 'No audio selected.';
    }

    final duration = audio.duration;

    if (audio.isRecording && duration != null) {
      return '${audio.displayName}\n'
          '${_speakableSeconds(duration)}\n'
          '${_formatFileSize(audio.sizeBytes)}';
    }

    return '${audio.name}\n'
        '${_formatFileSize(audio.sizeBytes)}';
  }

  String get _selectedAudioSemanticLabel {
    final error = _selectionError;

    if (error != null) {
      return 'Audio selection error. $error';
    }

    final audio = _selectedAudio;

    if (audio == null) {
      return 'Selected audio. '
          'No audio selected.';
    }

    final duration = audio.duration;

    if (audio.isRecording && duration != null) {
      return 'Selected audio. '
          'Guitar recording, '
          '${_speakableSeconds(duration)} long.';
    }

    return 'Selected WAV file. '
        '${audio.name}. '
        'File size '
        '${_formatFileSize(audio.sizeBytes)}.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GUITAR')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                headingLevel: 1,
                child: Text(
                  'Recognize guitar chords',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Choose a WAV audio file and '
                'ChordAssist will identify its '
                'prevailing chord progression.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              _StatusCard(
                title: 'Analysis service',
                message: _serviceStatus,
                semanticLabel:
                    'Analysis service. '
                    '$_serviceStatus',
                isError: !_isCheckingService && !_serviceReady,
              ),

              // The retry control stays in the tree while a check runs
              // (disabled, with a spinner) so the layout does not jump
              // when the button would otherwise disappear and reappear.
              if (!_serviceReady) ...[
                const SizedBox(height: 12),
                Semantics(
                  hint: _isCheckingService
                      ? 'A connection check is in progress.'
                      : 'Attempts to reconnect to '
                            'the chord analysis service.',
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _isCheckingService
                          ? null
                          : _checkAnalysisService,
                      icon: _isCheckingService
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _isCheckingService
                            ? 'Checking connection'
                            : 'Retry connection',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ],
              Semantics(
                headingLevel: 2,
                child: Text(
                  'Voice control',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusCard(
                        title: 'Voice status',
                        message: _voiceController.statusMessage,
                        semanticLabel:
                            'Voice control. '
                            '${_voiceController.statusMessage}',
                        isError:
                            _voiceController.state ==
                            VoiceControlState.unavailable,
                      ),

                      const SizedBox(height: 12),

                      _PrimaryActionButton(
                        icon: Icons.mic,
                        label: _voiceController.isSessionActive
                            ? 'Voice control active'
                            : 'Listen for a command',
                        semanticHint: _voiceController.isSessionActive
                            ? 'ChordAssist voice control '
                                  'is already running.'
                            : 'Starts listening for '
                                  'a spoken ChordAssist command.',
                        onPressed: _voiceController.canStartListening
                            ? () {
                                _voiceController.startManualSession();
                              }
                            : null,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),
              _PrimaryActionButton(
                icon: Icons.audio_file,
                label: _isPickingFile
                    ? 'Opening file picker'
                    : 'Choose WAV file',
                semanticHint:
                    'Opens the file picker to '
                    'select a WAV guitar recording.',
                onPressed: _isPickingFile || _isAnalyzing ? null : _pickWavFile,
              ),
              const SizedBox(height: 16),
              _PrimaryActionButton(
                icon: Icons.fiber_manual_record,
                label: 'Record guitar',
                semanticHint:
                    'Records guitar audio with the '
                    'phone microphone for up to sixty seconds.',
                onPressed: _isPickingFile || _isAnalyzing
                    ? null
                    : _recordGuitarFromButton,
              ),
              const SizedBox(height: 16),
              _StatusCard(
                title: _selectionError == null
                    ? 'Selected audio'
                    : 'Audio selection error',
                message: _selectedAudioMessage,
                semanticLabel: _selectedAudioSemanticLabel,
                isError: _selectionError != null,
              ),
              const SizedBox(height: 24),
              _PrimaryActionButton(
                icon: Icons.graphic_eq,
                label: _isAnalyzing ? 'Analyzing audio' : 'Analyze audio',
                semanticHint: _isAnalyzing
                    ? 'Chord analysis is currently '
                          'in progress.'
                    : !_serviceReady
                    ? 'The analysis service must be '
                          'available before analyzing audio.'
                    : _hasValidSelection
                    ? 'Analyzes the selected WAV file '
                          'using Basic Pitch chord recognition.'
                    : 'Choose a WAV file before '
                          'analyzing audio.',
                onPressed: _hasValidSelection && _serviceReady && !_isAnalyzing
                    ? _analyzeSelectedAudio
                    : null,
              ),
              const SizedBox(height: 40),
              Semantics(
                headingLevel: 2,
                child: Text(
                  'Results',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ResultCard(
                isAnalyzing: _isAnalyzing,
                result: _analysisResult,
                error: _analysisError,
              ),
              if (_analysisResult != null) ...[
                const SizedBox(height: 16),

                Semantics(
                  expanded: _showSegmentDetails,
                  hint: _showSegmentDetails
                      ? 'Hides the individual '
                            'analysis segments.'
                      : 'Shows each detected segment '
                            'with its time range.',
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showSegmentDetails = !_showSegmentDetails;
                        });
                      },
                      icon: Icon(
                        _showSegmentDetails
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      label: Text(
                        _showSegmentDetails
                            ? 'Hide segment details'
                            : 'Show segment details',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),

                if (_showSegmentDetails) ...[
                  const SizedBox(height: 16),

                  _SegmentDetails(segments: _analysisResult!.segments),
                ],
              ],
              const SizedBox(height: 24),
              _PrimaryActionButton(
                icon: Icons.volume_up,
                label: 'Read result aloud',
                semanticHint: _analysisResult == null
                    ? 'Analyze a WAV file before '
                          'reading the result aloud.'
                    : 'Reads the recognized chord '
                          'progression and uncertain '
                          'segments aloud.',
                onPressed: _analysisResult != null && !_isAnalyzing
                    ? _readResultAloud
                    : null,
              ),
              const SizedBox(height: 24),
              Semantics(
                headingLevel: 2,
                child: Text(
                  'Play Along',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _playAlongController,
                builder: (context, _) {
                  final playAlong = _playAlongController;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (playAlong.isActive) ...[
                        _StatusCard(
                          title: 'Play Along',
                          message: playAlong.isPaused
                              ? 'Play Along is paused.'
                              : 'Now playing: '
                                    '${playAlong.currentCue ?? 'starting'}',
                          semanticLabel: playAlong.isPaused
                              ? 'Play Along is paused.'
                              : 'Play Along. Now playing '
                                    '${playAlong.currentCue ?? 'audio'}.',
                          isError: false,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!playAlong.isActive)
                        _PrimaryActionButton(
                          icon: Icons.play_arrow,
                          label: 'Play Along',
                          semanticHint: _analysisResult == null
                              ? 'Analyze audio before using '
                                    'Play Along.'
                              : 'Replays the analyzed audio and '
                                    'announces each recognized chord.',
                          onPressed:
                              _analysisResult != null &&
                                  _selectedAudio != null &&
                                  !_isAnalyzing
                              ? _startPlayAlongFromButton
                              : null,
                        ),
                      if (playAlong.isPlaying) ...[
                        _PrimaryActionButton(
                          icon: Icons.pause,
                          label: 'Pause',
                          semanticHint: 'Pauses Play Along playback.',
                          onPressed: _pausePlayAlong,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (playAlong.isPaused) ...[
                        _PrimaryActionButton(
                          icon: Icons.play_arrow,
                          label: 'Resume',
                          semanticHint: 'Resumes Play Along playback.',
                          onPressed: _resumePlayAlong,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (playAlong.isActive)
                        _PrimaryActionButton(
                          icon: Icons.stop,
                          label: 'Stop play along',
                          semanticHint:
                              'Stops Play Along and returns '
                              'to voice control.',
                          onPressed: _stopPlayAlongFromButton,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.semanticHint,
    required this.onPressed,
  });

  final IconData icon;

  final String label;

  final String semanticHint;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: semanticHint,
      child: SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, semanticLabel: null),
          label: Text(label, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.message,
    required this.semanticLabel,
    required this.isError,
  });

  final String title;

  final String message;

  final String semanticLabel;

  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Deliberately NOT a live region: on-device testing showed
    // TalkBack announcing every status change while the recognizer was
    // listening, so the app heard the screen reader (and its own
    // status echoes) as commands. The app's own TTS is the
    // announcement channel; TalkBack users focus the card to read it.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isError ? colorScheme.error : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.isAnalyzing,
    required this.result,
    required this.error,
  });

  final bool isAnalyzing;

  final ChordAnalysisResult? result;

  final String? error;

  String get _semanticLabel {
    if (isAnalyzing) {
      return 'Analysis in progress. '
          'Analyzing the selected WAV file '
          'using Basic Pitch.';
    }

    if (error != null) {
      return 'Analysis failed. $error';
    }

    final currentResult = result;

    if (currentResult == null) {
      return 'Analysis result. '
          'No analysis yet.';
    }

    final readable = currentResult.readableProgression;

    if (readable.isEmpty) {
      return 'Analysis complete. '
          'No reliable chord progression '
          'was detected.';
    }

    return 'Analysis complete. '
        '${currentResult.speechText}';
  }

  @override
  Widget build(BuildContext context) {
    final currentResult = result;

    // Not a live region for the same reason as _StatusCard: the voice
    // flow already speaks the result, and TalkBack reading the full
    // progression over that speech (and into the microphone) made the
    // result impossible to follow on the device.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: isAnalyzing
              ? _buildLoading(context)
              : error != null
              ? _buildError(context)
              : currentResult != null
              ? _buildResult(context, currentResult)
              : _buildEmpty(context),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            'Analyzing audio with '
            'Basic Pitch...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analysis failed',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(error!, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }

  Widget _buildResult(BuildContext context, ChordAnalysisResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chord progression',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          result.progressionText,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          'Detected '
          '${result.recognizedChordSegments.length} '
          'recognized chord segments',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (result.uncertainSegmentCount > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Uncertain segments: '
            '${result.uncertainSegmentCount}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Audio duration: '
          '${result.audioDurationSec.toStringAsFixed(1)} seconds',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Analysis time: '
          '${result.latencyMs.toStringAsFixed(0)} ms',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chord progression',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text('No analysis yet.', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _SegmentDetails extends StatelessWidget {
  const _SegmentDetails({required this.segments});

  final List<ChordSegment> segments;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const _StatusCard(
        title: 'Segment details',
        message: 'No analysis segments were returned.',
        semanticLabel:
            'Segment details. '
            'No analysis segments were returned.',
        isError: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          headingLevel: 3,
          child: Text(
            'Segment details',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(height: 12),

        for (var index = 0; index < segments.length; index++) ...[
          _SegmentCard(index: index + 1, segment: segments[index]),

          if (index < segments.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({required this.index, required this.segment});

  final int index;

  final ChordSegment segment;

  String _formatTime(double seconds) {
    return seconds.toStringAsFixed(1);
  }

  String get _timeText {
    return '${_formatTime(segment.start)} '
        'to ${_formatTime(segment.end)} '
        'seconds';
  }

  String get _confidenceText {
    final percentage = (segment.confidence * 100).round();

    return 'Confidence $percentage percent';
  }

  String get _semanticLabel {
    final buffer = StringBuffer();

    buffer.write('Segment $index. ');

    buffer.write('${segment.readableLabel}. ');

    buffer.write(
      'From ${_formatTime(segment.start)} '
      'to ${_formatTime(segment.end)} '
      'seconds.',
    );

    if (segment.isRecognizedChord) {
      buffer.write(' $_confidenceText.');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Segment $index',
                style: Theme.of(context).textTheme.labelLarge,
              ),

              const SizedBox(height: 6),

              Text(
                segment.readableLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              Text(_timeText, style: Theme.of(context).textTheme.bodyLarge),

              if (segment.isRecognizedChord) ...[
                const SizedBox(height: 4),

                Text(
                  _confidenceText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
