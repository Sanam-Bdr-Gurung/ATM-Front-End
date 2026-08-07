import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

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

  bool get _hasValidSelection {
    return _selectedFile != null &&
        _selectedFileSize != null &&
        _selectionError == null;
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

  void _showAnalysisPendingMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'WAV file is ready. '
          'Backend analysis will be connected '
          'in the next checkpoint.',
        ),
      ),
    );
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
              _PrimaryActionButton(
                icon: Icons.audio_file,
                label: _isPickingFile
                    ? 'Opening file picker'
                    : 'Choose WAV file',
                semanticHint:
                    'Opens the file picker to '
                    'select a WAV guitar recording.',
                onPressed: _isPickingFile ? null : _pickWavFile,
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
                label: 'Analyze audio',
                semanticHint: _hasValidSelection
                    ? 'Analyzes the selected WAV '
                          'file for its chord '
                          'progression.'
                    : 'Choose a WAV file before '
                          'analyzing audio.',
                onPressed: _hasValidSelection
                    ? _showAnalysisPendingMessage
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
              const _ResultCard(),
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
  const _ResultCard();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: 'Analysis result. No analysis yet.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
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
                'No analysis yet.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
