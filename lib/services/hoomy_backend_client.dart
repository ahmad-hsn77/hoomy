import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

const Object _omitted = Object();

class HoomyBackendClient {
  HoomyBackendClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _httpClient;
  String? _token;
  io.Socket? _socket;

  bool get isAuthenticated => _token != null;
  String? get token => _token;

  void restoreToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
    _socket?.dispose();
    _socket = null;
  }

  Future<Map<String, dynamic>> register({
    required String name,
    String? email,
    String? phone,
    String? password,
    bool childMode = false,
  }) async {
    final payload = await _post('/auth/register', {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      'childMode': childMode,
    });
    _token = payload['token'] as String?;
    return payload;
  }

  Future<Map<String, dynamic>> login({
    String? email,
    String? phone,
    String? childName,
    String? password,
  }) async {
    final payload = await _post('/auth/login', {
      'email': email,
      'phone': phone,
      'childName': childName,
      'password': password,
    });
    _token = payload['token'] as String?;
    return payload;
  }

  Future<Map<String, dynamic>> requestPasswordReset({
    String? email,
    String? phone,
  }) {
    return _post('/auth/forgot-password', {
      'email': email,
      'phone': phone,
    });
  }

  Future<Map<String, dynamic>> resetPassword({
    String? email,
    String? phone,
    required String newPassword,
  }) {
    return _post('/auth/reset-password', {
      'email': email,
      'phone': phone,
      'newPassword': newPassword,
    });
  }

  Future<Map<String, dynamic>> getCurrentUser() => _get('/auth/me');

  Future<Map<String, dynamic>> getAppUpdate({
    required String currentVersion,
  }) {
    final encodedVersion = Uri.encodeQueryComponent(currentVersion);
    return _get('/app/update?currentVersion=$encodedVersion');
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    Object? phone = _omitted,
    Object? birthDate = _omitted,
  }) {
    return _put('/users/me/profile', {
      if (name != null) 'name': name,
      if (!identical(phone, _omitted)) 'phone': phone,
      if (!identical(birthDate, _omitted)) 'birthDate': birthDate,
    });
  }

  Future<Map<String, dynamic>> registerFcmToken(String token) {
    return _post('/devices/fcm-token', {'token': token});
  }

  Future<Map<String, dynamic>> updateNotificationPreferences({
    required bool needAlerts,
    required bool emergencyAlerts,
    required bool chatMessages,
  }) {
    return _put('/users/me/notification-preferences', {
      'needAlerts': needAlerts,
      'emergencyAlerts': emergencyAlerts,
      'chatMessages': chatMessages,
    });
  }

  Future<Map<String, dynamic>> createHouse({
    required String name,
    required String role,
    String? address,
    Map<String, double>? location,
  }) {
    return _post('/houses', {
      'name': name,
      'role': role,
      'address': address,
      'location': location,
    });
  }

  Future<Map<String, dynamic>> getHouseState(String houseId) =>
      _get('/houses/$houseId/state');

  Future<Map<String, dynamic>> getHouseSummary(String houseId) =>
      _get('/houses/$houseId/summary');

  Future<Map<String, dynamic>> getHouseMembers(String houseId) =>
      _get('/houses/$houseId/sections/members');

  Future<Map<String, dynamic>> getHouseAlerts(String houseId) =>
      _get('/houses/$houseId/sections/alerts');

  Future<Map<String, dynamic>> getHouseReminders(String houseId) =>
      _get('/houses/$houseId/sections/reminders');

  Future<Map<String, dynamic>> getHouseMessages(
    String houseId, {
    int? limit,
    String? before,
  }) {
    final query = <String>[
      if (limit != null) 'limit=$limit',
      if (before != null) 'before=${Uri.encodeQueryComponent(before)}',
    ].join('&');
    return _get(
        '/houses/$houseId/sections/messages${query.isEmpty ? '' : '?$query'}');
  }

  Future<Map<String, dynamic>> getHouseShortcuts(String houseId) =>
      _get('/houses/$houseId/sections/shortcuts');

  Future<Map<String, dynamic>> updateHouseLocation({
    required String houseId,
    required Map<String, double> location,
    required String address,
  }) {
    return _put('/houses/$houseId/location', {
      'location': location,
      'address': address,
    });
  }

  Future<Map<String, dynamic>> joinHouse({
    required String houseCode,
    required String relation,
  }) {
    return _post('/houses/join', {
      'houseCode': houseCode,
      'relation': relation,
    });
  }

  Future<Map<String, dynamic>> addMember({
    required String houseId,
    required String name,
    required String relation,
    String? email,
    String? phone,
    bool childMode = false,
  }) {
    return _post('/houses/$houseId/members', {
      'name': name,
      'relation': relation,
      'email': email,
      'phone': phone,
      'childMode': childMode,
    });
  }

  Future<Map<String, dynamic>> updateMyLocationStatus({
    required String houseId,
    required bool outsideHouse,
    Map<String, double>? location,
  }) {
    return _put('/houses/$houseId/members/me/status', {
      'outsideHouse': outsideHouse,
      'location': location,
    });
  }

  Future<Map<String, dynamic>> createAlert({
    required String houseId,
    required String title,
    String? note,
    String? quantity,
    bool emergency = false,
    List<String> targetMemberIds = const [],
  }) {
    return _post('/houses/$houseId/alerts', {
      'title': title,
      'note': note,
      'quantity': quantity,
      'emergency': emergency,
      'targetMemberIds': targetMemberIds,
    });
  }

  Future<Map<String, dynamic>> markAlertBought({
    required String houseId,
    required String alertId,
    String? quantity,
    String? price,
  }) {
    return _post('/houses/$houseId/alerts/$alertId/bought', {
      'quantity': quantity,
      'price': price,
    });
  }

  Future<Map<String, dynamic>> deleteAlert({
    required String houseId,
    required String alertId,
  }) {
    return _delete('/houses/$houseId/alerts/$alertId');
  }

  Future<Map<String, dynamic>> createReminder({
    required String houseId,
    required String title,
    required String dueAt,
    List<String> ringTimes = const [],
    String recurrence = 'once',
    List<int> recurrenceWeekdays = const [],
    String? note,
    bool isBirthday = false,
    String? birthdayMemberId,
  }) {
    return _post('/houses/$houseId/reminders', {
      'title': title,
      'note': note,
      'dueAt': dueAt,
      'ringTimes': ringTimes,
      'recurrence': recurrence,
      'recurrenceWeekdays': recurrenceWeekdays,
      'isBirthday': isBirthday,
      'birthdayMemberId': birthdayMemberId,
    });
  }

  Future<Map<String, dynamic>> updateReminder({
    required String houseId,
    required String reminderId,
    required String title,
    required String dueAt,
    List<String> ringTimes = const [],
    String recurrence = 'once',
    List<int> recurrenceWeekdays = const [],
    String? note,
    bool isBirthday = false,
    String? birthdayMemberId,
  }) {
    return _put('/houses/$houseId/reminders/$reminderId', {
      'title': title,
      'note': note,
      'dueAt': dueAt,
      'ringTimes': ringTimes,
      'recurrence': recurrence,
      'recurrenceWeekdays': recurrenceWeekdays,
      'isBirthday': isBirthday,
      'birthdayMemberId': birthdayMemberId,
    });
  }

  Future<Map<String, dynamic>> deleteReminder({
    required String houseId,
    required String reminderId,
  }) {
    return _delete('/houses/$houseId/reminders/$reminderId');
  }

  Future<Map<String, dynamic>> sendMessage({
    required String houseId,
    required String text,
    String? replyToMessageId,
    bool audio = false,
    String? audioBase64,
    String? audioMimeType,
    int? audioDurationSeconds,
    bool image = false,
    String? imageBase64,
    String? imageMimeType,
  }) {
    return _post('/houses/$houseId/messages', {
      'text': text,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      'audio': audio,
      if (audioBase64 != null) 'audioBase64': audioBase64,
      if (audioMimeType != null) 'audioMimeType': audioMimeType,
      if (audioDurationSeconds != null)
        'audioDurationSeconds': audioDurationSeconds,
      'image': image,
      if (imageBase64 != null) 'imageBase64': imageBase64,
      if (imageMimeType != null) 'imageMimeType': imageMimeType,
    });
  }

  Future<Map<String, dynamic>> editMessage({
    required String houseId,
    required String messageId,
    required String text,
  }) {
    return _put('/houses/$houseId/messages/$messageId', {
      'text': text,
    });
  }

  Future<Map<String, dynamic>> markMessageReceived({
    required String houseId,
    required String messageId,
  }) {
    return _post('/houses/$houseId/messages/$messageId/received', {});
  }

  Future<Map<String, dynamic>> markMessagesSeen({
    required String houseId,
  }) {
    return _post('/houses/$houseId/messages/seen', {});
  }

  Future<Map<String, dynamic>> reactToMessage({
    required String houseId,
    required String messageId,
    String? emoji,
  }) {
    return _put('/houses/$houseId/messages/$messageId/reaction', {
      'emoji': emoji,
    });
  }

  Future<Map<String, dynamic>> createShortcut({
    required String houseId,
    required String label,
    required String actionType,
    required String actionValue,
  }) {
    return _post('/houses/$houseId/shortcuts', {
      'label': label,
      'actionType': actionType,
      'actionValue': actionValue,
    });
  }

  Future<Map<String, dynamic>> updateShortcut({
    required String houseId,
    required String shortcutId,
    required String label,
    required String actionType,
    required String actionValue,
  }) {
    return _put('/houses/$houseId/shortcuts/$shortcutId', {
      'label': label,
      'actionType': actionType,
      'actionValue': actionValue,
    });
  }

  Future<Map<String, dynamic>> deleteShortcut({
    required String houseId,
    required String shortcutId,
  }) {
    return _delete('/houses/$houseId/shortcuts/$shortcutId');
  }

  void connectSocket({
    required String houseId,
    required void Function(String event, dynamic data) onEvent,
  }) {
    final token = _token;
    if (token == null) return;

    _socket?.dispose();
    _socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    for (final event in [
      'alertCreated',
      'alertBought',
      'alertDeleted',
      'reminderCreated',
      'reminderUpdated',
      'reminderDeleted',
      'messageCreated',
      'messageUpdated',
      'shortcutCreated',
      'shortcutUpdated',
      'shortcutDeleted',
      'memberAdded',
      'memberUpdated'
    ]) {
      _socket!.on(event, (data) => onEvent(event, data));
    }

    _socket!
      ..connect()
      ..emit('joinHouse', houseId);
  }

  void dispose() {
    _socket?.dispose();
    _httpClient.close();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _httpClient.get(_uri(path), headers: _headers());
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _put(
      String path, Map<String, dynamic> body) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final response = await _httpClient.delete(_uri(path), headers: _headers());
    return _decode(response);
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw HoomyBackendException(
          response.statusCode, body['message']?.toString() ?? 'Request failed');
    }
    return body;
  }
}

class HoomyBackendException implements Exception {
  HoomyBackendException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HoomyBackendException($statusCode): $message';
}
