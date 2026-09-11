import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoomy/views/chat/voice_recording_gesture.dart';

void main() {
  group('resolveVoiceRecordingGesture', () {
    test('cancels when sliding left in LTR', () {
      final state = resolveVoiceRecordingGesture(
        start: Offset.zero,
        current: const Offset(-95, 0),
        textDirection: TextDirection.ltr,
      );

      expect(state.action, VoiceRecordingGestureAction.cancel);
      expect(state.cancelProgress, greaterThan(0.8));
      expect(state.lockProgress, 0);
    });

    test('cancels when sliding toward the visual left in RTL', () {
      final state = resolveVoiceRecordingGesture(
        start: Offset.zero,
        current: const Offset(95, 0),
        textDirection: TextDirection.rtl,
      );

      expect(state.action, VoiceRecordingGestureAction.cancel);
      expect(state.cancelProgress, greaterThan(0.8));
    });

    test('locks when sliding up and lock wins over cancel', () {
      final state = resolveVoiceRecordingGesture(
        start: Offset.zero,
        current: const Offset(-120, -120),
        textDirection: TextDirection.ltr,
      );

      expect(state.action, VoiceRecordingGestureAction.lock);
      expect(state.lockProgress, 1);
    });

    test('keeps recording below thresholds', () {
      final state = resolveVoiceRecordingGesture(
        start: Offset.zero,
        current: const Offset(-30, -20),
        textDirection: TextDirection.ltr,
      );

      expect(state.action, VoiceRecordingGestureAction.keepRecording);
      expect(state.cancelProgress, closeTo(30 / 110, 0.001));
      expect(state.lockProgress, closeTo(20 / 110, 0.001));
    });
  });
}
