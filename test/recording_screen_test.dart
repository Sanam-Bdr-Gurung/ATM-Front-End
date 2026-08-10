import 'package:chords_finder/screens/recording_screen.dart';
import 'package:chords_finder/services/recording_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecordingService extends RecordingService {
  bool failOnStart = false;

  @override
  Future<String> start() async {
    if (failOnStart) {
      throw const RecordingException(
        'Recording could not start. '
        'Check microphone access and try again.',
      );
    }

    return '/cache/chordassist_recording.wav';
  }

  @override
  Future<String> stop() async {
    return '/cache/chordassist_recording.wav';
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _Launcher extends StatefulWidget {
  const _Launcher({required this.service, required this.onOutcome});

  final RecordingService service;

  final void Function(RecordingOutcome?) onOutcome;

  @override
  State<_Launcher> createState() {
    return _LauncherState();
  }
}

class _LauncherState extends State<_Launcher> {
  Future<void> _open() async {
    final outcome = await Navigator.of(context).push<RecordingOutcome>(
      MaterialPageRoute<RecordingOutcome>(
        builder: (_) {
          return RecordingScreen(recordingService: widget.service);
        },
      ),
    );

    widget.onOutcome(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(onPressed: _open, child: const Text('Open')),
      ),
    );
  }
}

void main() {
  Future<void> openRecordingScreen(
    WidgetTester tester,
    RecordingService service,
    void Function(RecordingOutcome?) onOutcome,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _Launcher(service: service, onOutcome: onOutcome),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('RecordingScreen', () {
    testWidgets('exposes one accessible Stop recording control', (
      WidgetTester tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();

      await openRecordingScreen(tester, _FakeRecordingService(), (_) {});

      expect(find.text('Recording guitar'), findsOneWidget);

      final stopControl = tester.getSemantics(
        find.bySemanticsLabel('Stop recording'),
      );

      expect(stopControl.flagsCollection.isButton, isTrue);

      semanticsHandle.dispose();

      // Leave recording mode cleanly before the test tears down.
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping the surface stops and returns the result', (
      WidgetTester tester,
    ) async {
      RecordingOutcome? outcome;

      await openRecordingScreen(tester, _FakeRecordingService(), (value) {
        outcome = value;
      });

      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.result, isNotNull);
      expect(outcome!.result!.autoStopped, isFalse);

      // pumpAndSettle advances fake time in small steps, so allow a
      // little slack beyond the 5 pumped seconds.
      expect(
        outcome!.result!.duration,
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
      expect(outcome!.result!.duration, lessThan(const Duration(seconds: 7)));
    });

    testWidgets('stops automatically at the safety limit', (
      WidgetTester tester,
    ) async {
      RecordingOutcome? outcome;

      await openRecordingScreen(tester, _FakeRecordingService(), (value) {
        outcome = value;
      });

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.result, isNotNull);
      expect(outcome!.result!.autoStopped, isTrue);
      expect(outcome!.result!.duration, const Duration(seconds: 60));
    });

    testWidgets('reports a start failure and closes', (
      WidgetTester tester,
    ) async {
      RecordingOutcome? outcome;

      final service = _FakeRecordingService()..failOnStart = true;

      await openRecordingScreen(tester, service, (value) {
        outcome = value;
      });

      expect(outcome, isNotNull);
      expect(outcome!.errorMessage, contains('could not start'));
    });
  });
}
