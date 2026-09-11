import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/chat_message.dart';
import '../models/family_reminder.dart';
import '../models/need_alert.dart';
import 'chat_notification_state.dart';

final _notificationTapController = StreamController<String>.broadcast();

Stream<String> get hoomyNotificationTaps => _notificationTapController.stream;

class AlertNotificationService {
  AlertNotificationService._();

  static final AlertNotificationService instance = AlertNotificationService._();
  static const _audioChannel = MethodChannel('hoomy/audio');

  static const _emergencyChannelId = 'hoomy_emergency_alerts_alarm_v2';
  static const _emergencyChannelName = 'Emergency alerts';
  static const _alertChannelId = 'hoomy_need_alerts';
  static const _alertChannelName = 'Need alerts';
  static const _reminderChannelId = 'hoomy_reminders_alarm_v2';
  static const _reminderChannelName = 'Family reminders';
  static const _chatChannelId = 'hoomy_chat_messages_chime_v2';
  static const _chatChannelName = 'Family chat';
  static const _chatGroupKey = 'com.idea.hoomy.hoomy.FAMILY_CHAT';
  static const _chatNotificationTag = 'hoomy-family-chat';
  static const _chatSummaryNotificationId = 0x48434;
  static const _chatStatePrefsKey = 'hoomy_chat_notification_state';
  static const _reminderTimesPrefsPrefix = 'hoomy_reminder_scheduled_times.';
  static const _statusBarIcon = 'ic_notification_house';
  static const _emergencySound = 'emergency_ring';
  static const _reminderSound = 'reminder_ring';
  static const _messageSound = 'message_chime';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Set<String> _shownAlertIds = {};
  final Set<String> _shownMessageIds = {};
  bool _initialized = false;
  bool _timeZonesInitialized = false;
  String? _initialNotificationPayload;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_notification_house'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _notificationTapController.add(payload);
      },
    );
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      _initialNotificationPayload = launchPayload;
      _notificationTapController.add(launchPayload);
    }

    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _emergencyChannelId,
        _emergencyChannelName,
        description: 'Urgent house needs that should ring like a call.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_emergencySound),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertChannelId,
        _alertChannelName,
        description: 'House needs shared by family members.',
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: 'Important family reminders with a gentle ringtone.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_reminderSound),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description: 'New messages in your family chat.',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_messageSound),
      ),
    );

    _initialized = true;
  }

  String? takeInitialNotificationPayload() {
    final payload = _initialNotificationPayload;
    _initialNotificationPayload = null;
    return payload;
  }

  Future<void> showEmergencyAlert(NeedAlert alert) async {
    if (kIsWeb) return;
    if (!_shownAlertIds.add(alert.id)) return;
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _emergencyChannelId,
        _emergencyChannelName,
        channelDescription: 'Urgent house needs that should ring like a call.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_emergencySound),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ticker: 'Emergency house need',
        visibility: NotificationVisibility.public,
        icon: _statusBarIcon,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'emergency_ring.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _notifications.show(
      id: alert.id.hashCode & 0x7fffffff,
      title: 'Emergency need: ${alert.title}',
      body: alert.note.isEmpty ? 'A family member needs this now.' : alert.note,
      notificationDetails: details,
      payload: alert.id,
    );
  }

  Future<void> showNeedAlert(NeedAlert alert) async {
    if (alert.emergency) {
      await showEmergencyAlert(alert);
      return;
    }
    if (kIsWeb) return;
    if (!_shownAlertIds.add(alert.id)) return;
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        _alertChannelName,
        channelDescription: 'House needs shared by family members.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: _statusBarIcon,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      id: alert.id.hashCode & 0x7fffffff,
      title: 'House need: ${alert.title}',
      body: alert.note.isEmpty ? 'A family member added a need.' : alert.note,
      notificationDetails: details,
      payload: alert.id,
    );
  }

  Future<void> showChatMessage(ChatMessage message,
      {String? senderName}) async {
    if (kIsWeb) return;
    await initialize();

    final state = await _addChatNotificationLine(message, senderName);
    if (state.visibleLines.isEmpty) return;

    final latestLine = state.visibleLines.last.text;
    final unreadLabel = state.totalUnread == 1
        ? '1 new message'
        : '${state.totalUnread} new messages';
    final lines = state.visibleLines.map((line) => line.text).toList();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _chatChannelId,
        _chatChannelName,
        channelDescription: 'New messages in your family chat.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound(_messageSound),
        icon: _statusBarIcon,
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        tag: _chatNotificationTag,
        number: state.totalUnread,
        styleInformation: InboxStyleInformation(
          lines,
          contentTitle: 'Family chat',
          summaryText: unreadLabel,
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'message_chime.wav',
        threadIdentifier: _chatGroupKey,
      ),
    );

    await _notifications.show(
      id: _chatSummaryNotificationId,
      title: 'Family chat',
      body: latestLine,
      notificationDetails: details,
      payload: 'chat',
    );
  }

  Future<void> clearChatMessages({
    Iterable<String> messageIds = const [],
  }) async {
    if (kIsWeb) return;
    await initialize();
    for (final messageId in messageIds) {
      await _notifications.cancel(id: messageId.hashCode & 0x7fffffff);
    }
    await _notifications.cancel(id: _chatSummaryNotificationId);
    try {
      await _audioChannel.invokeMethod<void>('clearChatNotifications');
    } catch (_) {
      // Older app versions only had app-owned local chat notifications.
    }
    _shownMessageIds.clear();
    await _clearChatNotificationState();
  }

  Future<ChatNotificationState> _addChatNotificationLine(
    ChatMessage message,
    String? senderName,
  ) async {
    final state = await _readChatNotificationState();
    final sender = senderName ?? 'Family';
    final body = message.audio
        ? 'Voice message'
        : message.image
            ? 'Photo'
            : message.text;
    final lineText = message.system ? body : '$sender: $body';
    final nextState = state.add(
      ChatNotificationPreviewLine(
        messageId: message.id,
        text: lineText.trim().isEmpty ? 'New family message' : lineText,
      ),
    );
    if (identical(nextState, state)) return state;
    await _writeChatNotificationState(nextState);
    _shownMessageIds.add(message.id);
    return nextState;
  }

  Future<ChatNotificationState> _readChatNotificationState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatStatePrefsKey);
    if (raw == null || raw.isEmpty) return const ChatNotificationState();
    try {
      return ChatNotificationState.fromJson(jsonDecode(raw));
    } catch (_) {
      return const ChatNotificationState();
    }
  }

  Future<void> _writeChatNotificationState(ChatNotificationState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatStatePrefsKey, jsonEncode(state.toJson()));
  }

  Future<void> _clearChatNotificationState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatStatePrefsKey);
  }

  Future<void> showReminder(FamilyReminder reminder) async {
    if (kIsWeb) return;
    await initialize();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        _alertChannelName,
        channelDescription: 'House needs shared by family members.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        icon: _statusBarIcon,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      id: reminder.id.hashCode & 0x7fffffff,
      title: 'Family reminder: ${reminder.title}',
      body: reminder.note.isEmpty
          ? 'A family member added a reminder.'
          : reminder.note,
      notificationDetails: details,
      payload: reminder.id,
    );
  }

  Future<void> scheduleReminder(FamilyReminder reminder) async {
    if (kIsWeb) return;
    await initialize();
    _initializeTimeZones();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _reminderChannelId,
        _reminderChannelName,
        channelDescription:
            'Important family reminders with a gentle ringtone.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_reminderSound),
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        ticker: 'Family reminder',
        visibility: NotificationVisibility.public,
        icon: _statusBarIcon,
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'reminder_ring.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    final canUseExactAlarms = await _canUseExactAlarms();
    await _cancelStoredReminderTimes(reminder.id);
    final scheduledTimes = <String>[];
    if (reminder.repeatsDaily) {
      for (final ringTime in reminder.effectiveRingTimes) {
        final scheduledAt = _nextDailyReminderDate(ringTime);
        final scheduleKey = 'daily:$ringTime';
        await _scheduleReminderAt(
          reminder: reminder,
          ringTime: ringTime,
          scheduleKey: scheduleKey,
          scheduledAt: scheduledAt,
          details: details,
          useExactAlarm: canUseExactAlarms,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        scheduledTimes.add(scheduleKey);
      }
    } else if (reminder.repeatsWeekly) {
      for (final day in reminder.effectiveWeekdays) {
        for (final ringTime in reminder.effectiveRingTimes) {
          final scheduledAt = _nextWeeklyReminderDate(day, ringTime);
          final scheduleKey = 'weekly:$day:$ringTime';
          await _scheduleReminderAt(
            reminder: reminder,
            ringTime: ringTime,
            scheduleKey: scheduleKey,
            scheduledAt: scheduledAt,
            details: details,
            useExactAlarm: canUseExactAlarms,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
          scheduledTimes.add(scheduleKey);
        }
      }
    } else {
      for (final ringTime in reminder.effectiveRingTimes) {
        final scheduledAt = reminder.scheduledAtForRingTime(ringTime);
        final now = DateTime.now();
        if (!scheduledAt.isAfter(now)) {
          debugPrint(
            '[HoomyReminder] Skipped past reminder ${reminder.id} '
            '$ringTime at $scheduledAt. Now: $now',
          );
          continue;
        }
        await _scheduleReminderAt(
          reminder: reminder,
          ringTime: ringTime,
          scheduleKey: ringTime,
          scheduledAt: scheduledAt,
          details: details,
          useExactAlarm: canUseExactAlarms,
        );
        scheduledTimes.add(ringTime);
      }
    }
    await _writeScheduledReminderTimes(reminder.id, scheduledTimes);
    debugPrint(
      '[HoomyReminder] Reminder ${reminder.id} scheduled times: '
      '${scheduledTimes.join(', ')}',
    );
  }

  Future<void> cancelReminder(String reminderId) async {
    if (kIsWeb) return;
    await initialize();
    await _cancelStoredReminderTimes(reminderId);
  }

  Future<void> _scheduleReminderAt({
    required FamilyReminder reminder,
    required String ringTime,
    required String scheduleKey,
    required DateTime scheduledAt,
    required NotificationDetails details,
    required bool useExactAlarm,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final notificationId = _reminderNotificationId(reminder.id, scheduleKey);
    final scheduledDate = tz.TZDateTime.from(scheduledAt, tz.local);
    try {
      await _notifications.zonedSchedule(
        id: notificationId,
        title: 'Family reminder: ${reminder.title}',
        body: reminder.note.isEmpty
            ? 'It is time for this family reminder.'
            : reminder.note,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: useExactAlarm
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: 'reminder:${reminder.id}:$ringTime',
      );
      debugPrint(
        '[HoomyReminder] Scheduled reminder ${reminder.id} $ringTime '
        'at $scheduledDate with id $notificationId '
        'using ${useExactAlarm ? 'exact' : 'inexact'} alarms.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[HoomyReminder] Exact reminder scheduling failed for '
        '${reminder.id} $ringTime: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      await _notifications.zonedSchedule(
        id: notificationId,
        title: 'Family reminder: ${reminder.title}',
        body: reminder.note.isEmpty
            ? 'It is time for this family reminder.'
            : reminder.note,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: 'reminder:${reminder.id}:$ringTime',
      );
      debugPrint(
        '[HoomyReminder] Scheduled reminder ${reminder.id} $ringTime '
        'with inexact fallback using id $notificationId.',
      );
    }
  }

  DateTime _nextDailyReminderDate(String ringTime) {
    final now = DateTime.now();
    final time = _parseRingTime(ringTime, fallback: now);
    var scheduledAt =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = scheduledAt.add(const Duration(days: 1));
    }
    return scheduledAt;
  }

  DateTime _nextWeeklyReminderDate(int weekday, String ringTime) {
    final now = DateTime.now();
    final time = _parseRingTime(ringTime, fallback: now);
    var daysUntil = weekday - now.weekday;
    var scheduledAt =
        DateTime(now.year, now.month, now.day, time.hour, time.minute)
            .add(Duration(days: daysUntil));
    if (!scheduledAt.isAfter(now)) {
      scheduledAt = scheduledAt.add(const Duration(days: 7));
    }
    return scheduledAt;
  }

  DateTime _parseRingTime(String ringTime, {required DateTime fallback}) {
    final parts = ringTime.split(':');
    final hour =
        int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? fallback.hour;
    final minute =
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? fallback.minute;
    return DateTime(fallback.year, fallback.month, fallback.day, hour, minute);
  }

  Future<bool> _canUseExactAlarms() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    try {
      if (await android.canScheduleExactNotifications() == true) return true;
      return await android.requestExactAlarmsPermission() == true;
    } catch (error) {
      debugPrint('[HoomyReminder] Exact alarm permission check failed: $error');
      return false;
    }
  }

  Future<void> _cancelStoredReminderTimes(String reminderId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_reminderTimesPrefsPrefix$reminderId';
    final ringTimes = prefs.getStringList(key) ?? const <String>[];
    if (ringTimes.isEmpty) {
      await _notifications.cancel(
          id: _legacyReminderNotificationId(reminderId));
    }
    for (final ringTime in ringTimes) {
      await _notifications.cancel(
          id: _reminderNotificationId(reminderId, ringTime));
    }
    await prefs.remove(key);
  }

  Future<void> _writeScheduledReminderTimes(
    String reminderId,
    List<String> ringTimes,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_reminderTimesPrefsPrefix$reminderId';
    if (ringTimes.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setStringList(key, ringTimes);
    }
  }

  Future<void> playMessageSendCue() async {
    if (kIsWeb) return;
    try {
      await _audioChannel.invokeMethod<void>('playMessageChime');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
    await HapticFeedback.selectionClick();
  }

  Future<void> playMessageReceiveCue() async {
    if (kIsWeb) return;
    try {
      await _audioChannel.invokeMethod<void>('playMessageReceiveChime');
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  void _initializeTimeZones() {
    if (_timeZonesInitialized) return;
    tz_data.initializeTimeZones();
    _timeZonesInitialized = true;
  }

  int _reminderNotificationId(String reminderId, String ringTime) =>
      'reminder-due-$reminderId-$ringTime'.hashCode & 0x7fffffff;

  int _legacyReminderNotificationId(String reminderId) =>
      'reminder-due-$reminderId'.hashCode & 0x7fffffff;
}

