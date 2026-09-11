enum ShortcutType { call, sms, appMessage }

class QuickShortcut {
  final String id;
  final String label;
  final ShortcutType type;
  final String value;

  const QuickShortcut({
    required this.id,
    required this.label,
    required this.type,
    required this.value,
  });
}
