import 'package:flutter/widgets.dart';

enum VoiceRecordingGestureAction {
  keepRecording,
  cancel,
  lock,
}

class VoiceRecordingGestureState {
  const VoiceRecordingGestureState({
    required this.action,
    required this.delta,
    required this.cancelProgress,
    required this.lockProgress,
  });

  final VoiceRecordingGestureAction action;
  final Offset delta;
  final double cancelProgress;
  final double lockProgress;

  bool get shouldCancel => action == VoiceRecordingGestureAction.cancel;
  bool get shouldLock => action == VoiceRecordingGestureAction.lock;
}

VoiceRecordingGestureState resolveVoiceRecordingGesture({
  required Offset start,
  required Offset current,
  required TextDirection textDirection,
  double cancelThreshold = 80,
  double lockThreshold = 90,
  double progressDistance = 110,
}) {
  final delta = current - start;
  final horizontalDistance =
      textDirection == TextDirection.rtl ? delta.dx : -delta.dx;
  final verticalDistance = -delta.dy;
  final shouldLock = verticalDistance > lockThreshold;
  final shouldCancel = !shouldLock && horizontalDistance > cancelThreshold;

  return VoiceRecordingGestureState(
    action: shouldLock
        ? VoiceRecordingGestureAction.lock
        : shouldCancel
            ? VoiceRecordingGestureAction.cancel
            : VoiceRecordingGestureAction.keepRecording,
    delta: delta,
    cancelProgress: (horizontalDistance / progressDistance).clamp(0.0, 1.0),
    lockProgress: (verticalDistance / progressDistance).clamp(0.0, 1.0),
  );
}
