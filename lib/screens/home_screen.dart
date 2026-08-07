import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                header: true,
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
                label: 'Choose WAV file',
                semanticHint:
                    'Opens the file picker to select '
                    'a WAV guitar recording.',
                onPressed: () {},
              ),

              const SizedBox(height: 16),

              const _StatusCard(
                title: 'Selected audio',
                message: 'No audio selected.',
              ),

              const SizedBox(height: 24),

              _PrimaryActionButton(
                icon: Icons.graphic_eq,
                label: 'Analyze audio',
                semanticHint:
                    'Analyzes the selected audio '
                    'for its chord progression.',
                onPressed: null,
              ),

              const SizedBox(height: 40),

              Semantics(
                header: true,
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

              _PrimaryActionButton(
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
  const _StatusCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title. $message',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
