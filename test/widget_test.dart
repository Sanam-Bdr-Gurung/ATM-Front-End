import 'package:chords_finder/screens/home_screen.dart';
import 'package:chords_finder/services/chord_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _HealthyApiService extends ChordApiService {
  const _HealthyApiService();

  @override
  Future<HealthCheckResult> checkHealth() async {
    return const HealthCheckResult(
      ready: true,
      message: 'Analysis service is ready.',
    );
  }
}

class _OfflineApiService extends ChordApiService {
  const _OfflineApiService();

  @override
  Future<HealthCheckResult> checkHealth() async {
    return const HealthCheckResult(
      ready: false,
      message:
          'Could not connect to the '
          'analysis service.',
    );
  }
}

Widget _buildTestApp({required ChordApiService apiService}) {
  // Voice auto-start stays off: widget tests cannot run the native
  // speech channels, and faking SpeechRecognizer/TTS here is
  // explicitly out of scope. Native voice behavior is verified on a
  // physical device.
  return MaterialApp(
    home: HomeScreen(apiService: apiService, autoStartVoiceControl: false),
  );
}

void main() {
  group('HomeScreen', () {
    testWidgets('shows the accessible initial state', (
      WidgetTester tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildTestApp(apiService: const _HealthyApiService()),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recognize guitar chords'), findsOneWidget);

      expect(find.text('Analysis service is ready.'), findsOneWidget);

      expect(find.text('No audio selected.'), findsOneWidget);

      expect(find.text('No analysis yet.'), findsOneWidget);

      semanticsHandle.dispose();
    });

    testWidgets('uses the expected heading hierarchy', (
      WidgetTester tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildTestApp(apiService: const _HealthyApiService()),
      );

      await tester.pumpAndSettle();

      final mainHeading = tester.getSemantics(
        find.text('Recognize guitar chords'),
      );

      final voiceHeading = tester.getSemantics(find.text('Voice control'));

      final resultsHeading = tester.getSemantics(find.text('Results'));

      // 'Play Along' is both the section heading and the button label;
      // the heading comes first in the tree.
      final playAlongHeading = tester.getSemantics(
        find.text('Play Along').first,
      );

      expect(mainHeading.headingLevel, 1);

      expect(voiceHeading.headingLevel, 2);

      expect(resultsHeading.headingLevel, 2);

      expect(playAlongHeading.headingLevel, 2);

      semanticsHandle.dispose();
    });

    testWidgets('recording is available while Play Along waits '
        'for an analysis result', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(apiService: const _HealthyApiService()),
      );

      await tester.pumpAndSettle();

      final recordButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record guitar'),
      );

      final playAlongButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Play Along'),
      );

      expect(recordButton.onPressed, isNotNull);

      expect(playAlongButton.onPressed, isNull);

      expect(
        find.widgetWithText(FilledButton, 'Listen for a command'),
        findsOneWidget,
      );
    });

    testWidgets('keeps analysis actions disabled '
        'before WAV selection', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(apiService: const _HealthyApiService()),
      );

      await tester.pumpAndSettle();

      final analyzeButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Analyze audio'),
      );

      final readButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Read result aloud'),
      );

      expect(analyzeButton.onPressed, isNull);

      expect(readButton.onPressed, isNull);
    });

    testWidgets('shows retry when service '
        'is unavailable', (WidgetTester tester) async {
      await tester.pumpWidget(
        _buildTestApp(apiService: const _OfflineApiService()),
      );

      await tester.pumpAndSettle();

      expect(
        find.text(
          'Could not connect to the '
          'analysis service.',
        ),
        findsOneWidget,
      );

      expect(find.text('Retry connection'), findsOneWidget);

      final analyzeButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Analyze audio'),
      );

      expect(analyzeButton.onPressed, isNull);
    });

    testWidgets('meets Android accessibility '
        'guidelines', (WidgetTester tester) async {
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(
        _buildTestApp(apiService: const _HealthyApiService()),
      );

      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await expectLater(tester, meetsGuideline(textContrastGuideline));

      semanticsHandle.dispose();
    });
  });
}
