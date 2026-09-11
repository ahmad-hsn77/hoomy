class FamilyReminder {
  final String id;
  final String title;
  final String note;
  final DateTime dueAt;
  final List<String> ringTimes;
  final String createdBy;
  final bool isBirthday;
  final String? birthdayMemberId;
  final String recurrence;
  final List<int> recurrenceWeekdays;

  const FamilyReminder({
    required this.id,
    required this.title,
    required this.note,
    required this.dueAt,
    this.ringTimes = const [],
    required this.createdBy,
    this.isBirthday = false,
    this.birthdayMemberId,
    this.recurrence = ReminderRecurrence.once,
    this.recurrenceWeekdays = const [],
  });

  bool get repeatsDaily => recurrence == ReminderRecurrence.daily;
  bool get repeatsWeekly => recurrence == ReminderRecurrence.weekly;
  bool get isRecurring => repeatsDaily || repeatsWeekly;

  List<String> get effectiveRingTimes {
    if (ringTimes.isNotEmpty) return ringTimes;
    return [
      '${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}',
    ];
  }

  List<int> get effectiveWeekdays {
    if (repeatsWeekly && recurrenceWeekdays.isNotEmpty) {
      final values = recurrenceWeekdays
          .where((day) => day >= DateTime.monday && day <= DateTime.sunday)
          .toSet()
          .toList()
        ..sort();
      return values;
    }
    if (repeatsDaily) {
      return const [
        DateTime.monday,
        DateTime.tuesday,
        DateTime.wednesday,
        DateTime.thursday,
        DateTime.friday,
        DateTime.saturday,
        DateTime.sunday,
      ];
    }
    return const [];
  }

  DateTime scheduledAtForRingTime(String ringTime) {
    final parts = ringTime.split(':');
    final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? dueAt.hour;
    final minute =
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? dueAt.minute;
    return DateTime(dueAt.year, dueAt.month, dueAt.day, hour, minute);
  }
}

class ReminderRecurrence {
  const ReminderRecurrence._();

  static const once = 'once';
  static const daily = 'daily';
  static const weekly = 'weekly';

  static const values = [once, daily, weekly];

  static String normalize(Object? value) {
    final text = value?.toString();
    return values.contains(text) ? text! : once;
  }
}
