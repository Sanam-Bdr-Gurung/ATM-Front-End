import 'package:chords_finder/recording/recording_controller.dart';
import 'package:chords_finder/services/recording_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecordingService extends RecordingService {
  bool startCalled = false;
  bool stopCalled = false;
  bool cancelCalled = false;

  bool failOnStart = false;

  @override
  Future<String> start() async {
    if (failOnStart) {
      throw const RecordingException(
        'Recording could not start. '
        'Check microphone access and try again.',
      );
    }

    startCalled = true;

    return '/cache/chordassist_recording.wav';
  }

  @override
  Future<String> stop() async {
    stopCalled = true;

    return '/cache/chordassist_recording.wav';
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
  }

  bool disposeCalled = false;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
  }
}

void main() {
  group('RecordingController', () {
    test('start begins recording and elapsed advances', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        controller.start();
        fake.flushMicrotasks();

        expect(service.startCalled, isTrue);
        expect(controller.isRecording, isTrue);

        fake.elapse(const Duration(seconds: 12));

        expect(controller.elapsed, const Duration(seconds: 12));
        expect(controller.remaining, const Duration(seconds: 48));
      });
    });

    test('manual stop returns the elapsed duration', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        controller.start();
        fake.flushMicrotasks();

        fake.elapse(const Duration(milliseconds: 18400));

        RecordingResult? result;

        controller.stop().then((value) => result = value);
        fake.flushMicrotasks();

        expect(service.stopCalled, isTrue);
        expect(result, isNotNull);
        expect(result!.autoStopped, isFalse);
        expect(result!.duration, const Duration(milliseconds: 18400));
        expect(controller.phase, RecordingPhase.idle);
      });
    });

    test('safety timeout stops the recording automatically', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        RecordingResult? autoResult;

        controller.onAutoStopped = (result) => autoResult = result;

        controller.start();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 61));
        fake.flushMicrotasks();

        expect(service.stopCalled, isTrue);
        expect(autoResult, isNotNull);
        expect(autoResult!.autoStopped, isTrue);
        expect(autoResult!.duration, const Duration(seconds: 60));
        expect(controller.phase, RecordingPhase.idle);
      });
    });

    test('start failure surfaces a RecordingException', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService()..failOnStart = true;

        final controller = RecordingController(service: service);

        Object? thrown;

        controller.start().catchError((Object error) {
          thrown = error;
        });
        fake.flushMicrotasks();

        expect(thrown, isA<RecordingException>());
        expect(controller.phase, RecordingPhase.idle);
      });
    });

    test('cancel abandons the recording', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        controller.start();
        fake.flushMicrotasks();

        fake.elapse(const Duration(seconds: 5));

        controller.cancel();
        fake.flushMicrotasks();

        expect(service.cancelCalled, isTrue);
        expect(controller.phase, RecordingPhase.idle);
        expect(controller.elapsed, Duration.zero);
      });
    });

    test('stop without recording throws', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        Object? thrown;

        controller.stop().catchError((Object error) {
          thrown = error;

          return const RecordingResult(
            path: '',
            duration: Duration.zero,
            autoStopped: false,
          );
        });
        fake.flushMicrotasks();

        expect(thrown, isA<RecordingException>());
      });
    });

    test('dispose never disposes the shared recording service', () {
      // Regression: the controller is per-session, but the service (and
      // its platform recorder) is shared across sessions. Disposing the
      // service here broke every recording after the first one.
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final controller = RecordingController(service: service);

        controller.start();
        fake.flushMicrotasks();

        controller.stop();
        fake.flushMicrotasks();

        controller.dispose();

        expect(service.disposeCalled, isFalse);
      });
    });

    test('a second session on the same service records again', () {
      fakeAsync((fake) {
        final service = _FakeRecordingService();

        final first = RecordingController(service: service);

        first.start();
        fake.flushMicrotasks();

        first.stop();
        fake.flushMicrotasks();

        first.dispose();

        final second = RecordingController(service: service);

        second.start();
        fake.flushMicrotasks();

        expect(second.isRecording, isTrue);

        second.stop();
        fake.flushMicrotasks();

        second.dispose();

        expect(service.disposeCalled, isFalse);
      });
    });
  });
}
