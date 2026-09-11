List<DateTime> visibleMonthDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = first.subtract(Duration(days: first.weekday % 7));
  return List.generate(42, (index) => DateTime(start.year, start.month, start.day + index));
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String nameInitial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}
