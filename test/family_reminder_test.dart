import 'package:flutter_test/flutter_test.dart';
import 'package:hoomy/models/family_reminder.dart';

void main() {
  group('FamilyReminder', () {
    test('falls back to dueAt time when no ring times are stored', () {
      final reminder = FamilyReminder(
        id: 'r1',
        title: 'Gas',
        note: '',
        dueAt: DateTime(2026, 9, 5, 8, 30),
        createdBy: 'u1',
      );

      expect(reminder.effectiveRingTimes, ['08:30']);
    });

    test('builds scheduled datetimes for each ring time on the due date', () {
      final reminder = FamilyReminder(
        id: 'r1',
        title: 'Gas',
        note: '',
        dueAt: DateTime(2026, 9, 5),
        ringTimes: const ['08:00', '14:30', '21:00'],
        createdBy: 'u1',
      );

      expect(
        reminder.effectiveRingTimes
            .map(reminder.scheduledAtForRingTime)
            .toList(),
        [
          DateTime(2026, 9, 5, 8),
          DateTime(2026, 9, 5, 14, 30),
          DateTime(2026, 9, 5, 21),
        ],
      );
    });
  });
}
