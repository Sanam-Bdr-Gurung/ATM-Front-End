import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../services/chord_api_service.dart';
import '../models/chord_analysis.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() {
    return _HomeScreenState();
  }
}

class _HomeScreenState extends State<HomeScreen> {
  XFile? _selectedFile;

  int? _selectedFileSize;

  String? _selectionError;

  bool _isPickingFile = false;
  final ChordApiService _apiService = const ChordApiService();

  bool _isCheckingService = true;

  bool _serviceReady = false;

  String _serviceStatus = 'Checking analysis service.';
  bool _isAnalyzing = false;

  ChordAnalysisResult? _analysisResult;

  String? _analysisError;
  bool get _hasValidSelection {
    return _selectedFile != null &&
        _selectedFileSize != null &&
        _selectionError == null;
  }

  @override
  void initState() {
    super.initState();

    _checkAnalysisService();
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

  Future<void> _pickWavFile() async {
    if (_isPickingFile) {
      return;
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
        return;
      }

      if (file == null) {
        setState(() {
          _isPickingFile = false;
        });

        return;
      }

      final fileName = file.name.trim();

      if (!fileName.toLowerCase().endsWith('.wav')) {
        setState(() {
          _selectedFile = null;
          _selectedFileSize = null;
          _selectionError =
              'Unsupported audio file. '
              'Please choose a WAV file.';
          _isPickingFile = false;
        });

        return;
      }

      final fileSize = await file.length();

      if (!mounted) {
        return;
      }

      if (fileSize <= 0) {
        setState(() {
          _selectedFile = null;
          _selectedFileSize = null;
          _selectionError =
              'The selected WAV file is empty. '
              'Please choose another file.';
          _isPickingFile = false;
        });

        return;
      }

      setState(() {
        _selectedFile = file;
        _selectedFileSize = fileSize;
        _selectionError = null;
        _isPickingFile = false;

        _analysisResult = null;
        _analysisError = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedFile = null;
        _selectedFileSize = null;
        _selectionError =
            'The audio file could not be selected. '
            'Please try again.';
        _isPickingFile = false;
      });
    }
  }

  Future<void> _analyzeSelectedAudio() async {
    final file = _selectedFile;
    final fileSize = _selectedFileSize;

    if (file == null || fileSize == null || !_serviceReady || _isAnalyzing) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _analysisError = null;
    });

    try {
      final result = await _apiService.analyzeWav(
        fileStream: file.openRead(),
        fileLength: fileSize,
        fileName: file.name,
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

    final file = _selectedFile;

    if (file == null || _selectedFileSize == null) {
      return 'No audio selected.';
    }

    return '${file.name}\n'
        '${_formatFileSize(_selectedFileSize!)}';
  }

  String get _selectedAudioSemanticLabel {
    final error = _selectionError;

    if (error != null) {
      return 'Audio selection error. $error';
    }

    final file = _selectedFile;

    if (file == null || _selectedFileSize == null) {
      return 'Selected audio. '
          'No audio selected.';
    }

    return 'Selected WAV file. '
        '${file.name}. '
        'File size '
        '${_formatFileSize(_selectedFileSize!)}.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ChordAssist')),
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

              if (!_isCheckingService && !_serviceReady) ...[
                const SizedBox(height: 12),
                Semantics(
                  hint:
                      'Attempts to reconnect to '
                      'the chord analysis service.',
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _checkAnalysisService,
                      icon: const Icon(Icons.refresh),
                      label: const Text(
                        'Retry connection',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ],

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
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ResultCard(
                isAnalyzing: _isAnalyzing,
                result: _analysisResult,
                error: _analysisError,
              ),
              const SizedBox(height: 24),
              const _PrimaryActionButton(
                icon: Icons.volume_up,
                label: 'Read result aloud',
                semanticHint:
                    'Reads the detected chord '
                    'progression aloud.',
                onPressed: null,
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

    return Semantics(
      container: true,
      liveRegion: true,
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
        'Detected ${readable.length} '
        'harmonic segments. '
        'Chord progression: '
        '${readable.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final currentResult = result;

    return Semantics(
      container: true,
      liveRegion: true,
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
          '${result.harmonicSegments.length} '
          'harmonic segments',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
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
