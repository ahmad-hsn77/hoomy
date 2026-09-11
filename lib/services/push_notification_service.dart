import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/chat_message.dart';
import '../models/family_reminder.dart';
import '../models/need_alert.dart';
import 'alert_notification_service.dart';

final _pushDiagnosticsController =
    StreamController<String>.broadcast(sync: true);
final _remoteChatMessageController =
    StreamController<ChatMessage>.broadcast(sync: true);
final _stateRefreshRequestController =
    StreamController<String>.broadcast(sync: true);
final _chatOpenRequestController = StreamController<void>.broadcast(sync: true);

Stream<String> get hoomyPushDiagnostics => _pushDiagnosticsController.stream;
Stream<ChatMessage> get hoomyRemoteChatMessages =>
    _remoteChatMessageController.stream;
Stream<String> get hoomyStateRefreshRequests =>
    _stateRefreshRequestController.stream;
Stream<void> get hoomyChatOpenRequests => _chatOpenRequestController.stream;

void _pushDiagnostic(String message) {
  debugPrint(message);
  _pushDiagnosticsController.add(message);
}

@pragma('vm:entry-point')
Future<void> hoomyFirebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await AlertNotificationService.instance.initialize();
  _pushDiagnostic(
      'Push received in background: type=${message.data['type']} id=${message.messageId}');
  await _showForegroundRemoteMessage(message);
}

Future<void> _showAlertFromRemoteMessage(RemoteMessage message) async {
  if (message.data['type'] != 'alertCreated') return;

  final emergency = message.data['emergency'] == 'true';
  final title = message.notification?.title
          ?.replaceFirst('Emergency need: ', '')
          .replaceFirst('House need: ', '') ??
      message.data['title'] ??
      'House need';
  final body = message.notification?.body ?? message.data['body'] ?? '';

  await AlertNotificationService.instance.showNeedAlert(
    NeedAlert(
      id: message.data['alertId'] ?? message.messageId ?? title,
      title: title,
      note: body,
      emergency: emergency,
      createdBy: message.data['createdBy'] ?? '',
      createdAt: DateTime.now(),
    ),
  );
}

Future<void> _showMessageFromRemoteMessage(RemoteMessage message) async {
  if (message.data['type'] != 'messageCreated') return;

  final title = message.notification?.title ?? message.data['title'];
  final body = message.notification?.body ?? message.data['body'] ?? '';
  final chatMessage = ChatMessage(
    id: message.data['messageId'] ?? message.messageId ?? body,
    senderId: message.data['senderId'] ?? '',
    text: body,
    createdAt: DateTime.now(),
    system: message.data['system'] == 'true',
  );
  _remoteChatMessageController.add(chatMessage);
  final lowerBody = body.toLowerCase();
  if (chatMessage.system &&
      (lowerBody.contains('bought') || lowerBody.contains('done'))) {
    _stateRefreshRequestController.add('bought-message-push');
  }

  if (PushNotificationService.instance.isChatScreenVisible) return;
  await AlertNotificationService.instance.showChatMessage(
    chatMessage,
    senderName: title?.replaceFirst(' in family chat', ''),
  );
}

Future<void> _showReminderFromRemoteMessage(RemoteMessage message) async {
  if (message.data['type'] != 'reminderCreated') return;

  final title =
      message.notification?.title?.replaceFirst('Family reminder: ', '') ??
          message.data['title'] ??
          'Reminder';
  final body = message.notification?.body ?? message.data['body'] ?? '';
  await AlertNotificationService.instance.showReminder(
    FamilyReminder(
      id: message.data['reminderId'] ?? message.messageId ?? title,
      title: title,
      note: body,
      dueAt: DateTime.tryParse(message.data['dueAt'] ?? '') ?? DateTime.now(),
      ringTimes: _parseRingTimes(message.data['ringTimes']),
      createdBy: message.data['createdBy'] ?? '',
      isBirthday: message.data['isBirthday'] == 'true',
      birthdayMemberId: (message.data['birthdayMemberId'] ?? '').isEmpty
          ? null
          : message.data['birthdayMemberId'],
    ),
  );
}

List<String> _parseRingTimes(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    final values = jsonDecode(encoded);
    if (values is! List) return const [];
    return values.map((item) => item.toString()).toList();
  } catch (_) {
    return const [];
  }
}

Future<void> _showForegroundRemoteMessage(RemoteMessage message) async {
  _pushDiagnostic(
      'Push received in foreground: type=${message.data['type']} id=${message.messageId}');
  await _showAlertFromRemoteMessage(message);
  await _showMessageFromRemoteMessage(message);
  await _showReminderFromRemoteMessage(message);
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  bool _available = false;
  bool _chatScreenVisible = false;

  bool get isChatScreenVisible => _chatScreenVisible;

  void setChatScreenVisible(bool visible) {
    _chatScreenVisible = visible;
  }

  Stream<String> get tokenRefreshes {
    final messaging = _messaging;
    if (!_available || kIsWeb || messaging == null) return const Stream.empty();
    return messaging.onTokenRefresh;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      FirebaseMessaging.onBackgroundMessage(
        hoomyFirebaseMessagingBackgroundHandler,
      );
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final settings = await messaging.getNotificationSettings();
      _pushDiagnostic('Push permission: ${settings.authorizationStatus.name}');
      FirebaseMessaging.onMessage.listen(_showForegroundRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedRemoteMessage);
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleOpenedRemoteMessage(initialMessage);
      }
      _available = true;
    } catch (error) {
      _pushDiagnostic('Push init error: $error');
    }
  }

  Future<String?> currentToken() async {
    await initialize();
    final messaging = _messaging;
    if (!_available || kIsWeb || messaging == null) return null;

    try {
      final token = await messaging.getToken();
      _pushDiagnostic(token == null
          ? 'Push token is empty'
          : 'Push token ready: ${token.substring(0, token.length < 12 ? token.length : 12)}...');
      return token;
    } catch (error) {
      _pushDiagnostic('Push token error: $error');
      return null;
    }
  }

  void _handleOpenedRemoteMessage(RemoteMessage message) {
    if (message.data['type'] == 'messageCreated') {
      _chatOpenRequestController.add(null);
    }
  }
}
