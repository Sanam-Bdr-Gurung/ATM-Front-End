import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording/recording_controller.dart';
import '../services/recording_service.dart';

/// What the recording screen produced when it closed.
class RecordingOutcome {
  const RecordingOutcome.success(RecordingResult this.result)
    : errorMessage = null;

  const RecordingOutcome.failure(String this.errorMessage) : result = null;

  final RecordingResult? result;

  final String? errorMessage;
}

/// Dedicated recording mode: the whole screen is one accessible
/// Stop recording control, so the user cannot get lost in other
/// controls while the microphone records their guitar.
///
/// Voice commands are unavailable here by design — the microphone
/// belongs to the guitar. TalkBack users activate the single focused
/// button with the standard double-tap; sighted users tap anywhere.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.recordingService,
    this.maxDuration = const Duration(seconds: 60),
  });

  final RecordingService recordingService;

  final Duration maxDuration;

  @override
  State<RecordingScreen> createState() {
    return _RecordingScreenState();
  }
}

class _RecordingScreenState extends State<RecordingScreen> {
  late final RecordingController _controller;

  bool _finished = false;

  @override
  void initState() {
    super.initState();

    _controller = RecordingController(
      service: widget.recordingService,
      maxDuration: widget.maxDuration,
    );

    _controller.onAutoStopped = _handleAutoStopped;
    _controller.onRecordingError = _handleRecordingError;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecording();
    });
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // Haptics are a secondary signal and must never gate the flow.
      unawaited(HapticFeedback.heavyImpact());

      await _controller.start();
    } on RecordingException catch (error) {
      _close(RecordingOutcome.failure(error.message));
    } catch (_) {
      _close(
        const RecordingOutcome.failure(
          'Recording could not start. '
          'Check microphone access and try again.',
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_controller.isRecording) {
      return;
    }

    try {
      unawaited(HapticFeedback.heavyImpact());

      final result = await _controller.stop();

      _close(RecordingOutcome.success(result));
    } on RecordingException catch (error) {
      _close(RecordingOutcome.failure(error.message));
    }
  }

  void _handleAutoStopped(RecordingResult result) {
    HapticFeedback.heavyImpact();

    _close(RecordingOutcome.success(result));
  }

  void _handleRecordingError(String message) {
    _close(RecordingOutcome.failure(message));
  }

  void _close(RecordingOutcome outcome) {
    if (_finished || !mounted) {
      return;
    }

    _finished = true;

    Navigator.of(context).pop(outcome);
  }

  String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;

    final seconds = elapsed.inSeconds % 60;

    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = seconds.toString().padLeft(2, '0');

    return '$minuteText:$secondText';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // The back gesture stops the recording instead of abandoning it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _stopRecording();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.errorContainer,
        body: Semantics(
          button: true,
          label: 'Stop recording',
          hint: 'Stops the current guitar recording',
          excludeSemantics: true,
          child: InkWell(
            onTap: _stopRecording,
            child: SafeArea(
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic,
                      size: 72,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Recording guitar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        return Text(
                          _formatElapsed(_controller.elapsed),
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'STOP RECORDING\n'
                        'Tap anywhere on the screen.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
