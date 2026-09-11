class ChatNotificationPreviewLine {
  const ChatNotificationPreviewLine({
    required this.messageId,
    required this.text,
  });

  final String messageId;
  final String text;

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'text': text,
      };

  static ChatNotificationPreviewLine? fromJson(Object? value) {
    if (value is! Map) return null;
    final messageId = value['messageId']?.toString() ?? '';
    final text = value['text']?.toString() ?? '';
    if (messageId.isEmpty || text.isEmpty) return null;
    return ChatNotificationPreviewLine(messageId: messageId, text: text);
  }
}

class ChatNotificationState {
  const ChatNotificationState({
    this.totalUnread = 0,
    this.visibleLines = const [],
  });

  final int totalUnread;
  final List<ChatNotificationPreviewLine> visibleLines;

  ChatNotificationState add(ChatNotificationPreviewLine line) {
    if (visibleLines.any((item) => item.messageId == line.messageId)) {
      return this;
    }

    final nextLines = [...visibleLines, line];
    return ChatNotificationState(
      totalUnread: totalUnread + 1,
      visibleLines: nextLines.length <= 3
          ? nextLines
          : nextLines.sublist(nextLines.length - 3),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalUnread': totalUnread,
        'visibleLines': visibleLines.map((line) => line.toJson()).toList(),
      };

  static ChatNotificationState fromJson(Object? value) {
    if (value is! Map) return const ChatNotificationState();
    final lines = (value['visibleLines'] as List<dynamic>? ?? [])
        .map(ChatNotificationPreviewLine.fromJson)
        .whereType<ChatNotificationPreviewLine>()
        .toList();
    return ChatNotificationState(
      totalUnread: int.tryParse(value['totalUnread']?.toString() ?? '') ?? 0,
      visibleLines: lines.length <= 3 ? lines : lines.sublist(lines.length - 3),
    );
  }
}
