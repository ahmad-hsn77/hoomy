import 'package:flutter_test/flutter_test.dart';
import 'package:hoomy/services/chat_notification_state.dart';

void main() {
  group('ChatNotificationState', () {
    test('keeps total unread while showing only latest 3 lines oldest first',
        () {
      final state = const ChatNotificationState()
          .add(const ChatNotificationPreviewLine(
            messageId: '1',
            text: 'A: one',
          ))
          .add(const ChatNotificationPreviewLine(
            messageId: '2',
            text: 'B: two',
          ))
          .add(const ChatNotificationPreviewLine(
            messageId: '3',
            text: 'C: three',
          ))
          .add(const ChatNotificationPreviewLine(
            messageId: '4',
            text: 'D: four',
          ));

      expect(state.totalUnread, 4);
      expect(
        state.visibleLines.map((line) => line.text),
        ['B: two', 'C: three', 'D: four'],
      );
    });

    test('does not increment unread for duplicate visible messages', () {
      final state = const ChatNotificationState()
          .add(const ChatNotificationPreviewLine(
            messageId: '1',
            text: 'A: one',
          ))
          .add(const ChatNotificationPreviewLine(
            messageId: '1',
            text: 'A: one',
          ));

      expect(state.totalUnread, 1);
      expect(state.visibleLines, hasLength(1));
    });
  });
}
