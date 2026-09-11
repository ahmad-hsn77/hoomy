import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/config/app_config.dart';
import '../models/app_user.dart';
import '../models/app_update_info.dart';
import '../models/chat_message.dart';
import '../models/family_reminder.dart';
import '../models/house.dart';
import '../models/need_alert.dart';
import '../models/quick_shortcut.dart';
import '../services/alert_notification_service.dart';
import '../services/hoomy_backend_client.dart';
import '../services/hoomy_analytics_service.dart';
import '../services/location_service.dart';
import '../services/push_notification_service.dart';
import '../services/session_storage.dart';
import '../services/startup_logger.dart';

const Object _profileBirthDateUnchanged = Object();
const int _messagePageSize = 30;
const int _cachedMessageLimit = 30;

class AppViewModel extends ChangeNotifier {
  AppViewModel({
    required this.members,
    required this.alerts,
    required this.reminders,
    required this.messages,
    required this.shortcuts,
    HoomyBackendClient? backendClient,
    LocationService? locationService,
    SessionStorage? sessionStorage,
    AlertNotificationService? alertNotificationService,
    PushNotificationService? pushNotificationService,
  })  : _backendClient = backendClient ??
            HoomyBackendClient(baseUrl: AppConfig.backendBaseUrl),
        _locationService = locationService ?? LocationService(),
        _sessionStorage = sessionStorage ?? SessionStorage(),
        _alertNotificationService =
            alertNotificationService ?? AlertNotificationService.instance,
        _pushNotificationService =
            pushNotificationService ?? PushNotificationService.instance;

  AppUser? currentUser;
  House? house;
  final List<House> availableHouses = [];
  bool isBusy = false;
  String? selectingHouseId;
  bool isLoadingMembers = false;
  bool isLoadingAlerts = false;
  bool isLoadingReminders = false;
  bool isLoadingMessages = false;
  bool isLoadingOlderMessages = false;
  bool hasOlderMessages = true;
  bool isLoadingShortcuts = false;
  bool isRestoringSession = true;
  bool continuousLocationUpdates = false;
  String? errorMessage;
  int unreadChatMessageCount = 0;
  bool isChatVisible = false;
  String languageCode = 'en';
  String pushStatusMessage = 'Push notifications are not checked yet.';

  final List<AppUser> members;
  final List<NeedAlert> alerts;
  final List<FamilyReminder> reminders;
  final List<ChatMessage> messages;
  final List<QuickShortcut> shortcuts;
  final HoomyBackendClient _backendClient;
  final LocationService _locationService;
  final SessionStorage _sessionStorage;
  final AlertNotificationService _alertNotificationService;
  final PushNotificationService _pushNotificationService;
  String? _connectedHouseId;
  Timer? _locationUpdateTimer;
  StreamSubscription<String>? _pushTokenSubscription;
  StreamSubscription<String>? _pushDiagnosticsSubscription;
  StreamSubscription<ChatMessage>? _remoteChatMessageSubscription;
  StreamSubscription<String>? _stateRefreshRequestSubscription;
  final Set<String> _notifiedAlertIds = {};
  bool _deferredStartupStarted = false;

  factory AppViewModel.seeded() {
    final now = DateTime.now();
    return AppViewModel(
      members: [],
      alerts: [],
      reminders: [
        FamilyReminder(
          id: 'r1',
          title: 'Gas cylinder exchange',
          note: 'Check kitchen cylinder before dinner.',
          dueAt: DateTime(now.year, now.month, now.day + 2, 18),
          createdBy: 'system',
        ),
      ],
      messages: [],
      shortcuts: [],
    ).._listenForPushDiagnostics();
  }

  void _listenForPushDiagnostics() {
    _pushDiagnosticsSubscription ??= hoomyPushDiagnostics.listen((message) {
      pushStatusMessage = message;
      notifyListeners();
    });
    _remoteChatMessageSubscription ??=
        hoomyRemoteChatMessages.listen(_handleIncomingChatMessage);
    _stateRefreshRequestSubscription ??= hoomyStateRefreshRequests
        .listen((_) => refreshHouseState(silent: true));
  }

  List<NeedAlert> get openAlerts =>
      alerts.where((item) => item.status == AlertStatus.open).toList();

  int get emergencyAlertCount =>
      openAlerts.where((item) => item.emergency).length;

  bool get needsHouseSelection =>
      currentUser != null && house == null && availableHouses.length > 1;

  Future<void> restoreSession() async {
    StartupLogger.mark('Local storage/session restore started');
    isRestoringSession = true;
    notifyListeners();
    final bootstrap = await _sessionStorage.readBootstrapSession();
    continuousLocationUpdates = bootstrap.continuousLocationUpdates;
    languageCode = bootstrap.languageCode;
    final session = bootstrap.session;
    StartupLogger.mark(session == null
        ? 'Local storage/session restore finished: logged out'
        : 'Local storage/session restore finished: cached session found');
    if (session != null) {
      if (_isJwtExpired(session.token)) {
        StartupLogger.mark('Cached token expired; session cleared');
        await _clearSession();
        isRestoringSession = false;
        StartupLogger.mark('Splash hidden');
        notifyListeners();
        return;
      }
      _backendClient.restoreToken(session.token);
      _printLoginToken(session.token);
      currentUser =
          _parseUser(jsonDecode(session.userJson) as Map<String, dynamic>);
      var hasUsableCachedHouseState = false;
      if (session.houseStateJson != null) {
        try {
          _applyHouseState(
              jsonDecode(session.houseStateJson!) as Map<String, dynamic>);
          hasUsableCachedHouseState = true;
          StartupLogger.mark('Cached house state ready');
        } catch (error) {
          debugPrint(
              '[HoomyStartup] Cached house state could not be used: $error');
          _restoreCachedHouseOnly(session);
        }
      } else {
        _restoreCachedHouseOnly(session);
      }
      StartupLogger.mark(house == null
          ? 'Cached auth ready: no cached house'
          : 'Cached house ready');

      if (!hasUsableCachedHouseState) {
        await _refreshSessionBeforeFirstScreen();
      }
      unawaited(_refreshSessionAfterFirstFrame());
    }
    isRestoringSession = false;
    StartupLogger.mark('Splash hidden');
    notifyListeners();
  }

  Future<void> initializeDeferredStartupTasks() async {
    if (_deferredStartupStarted) return;
    _deferredStartupStarted = true;
    await Future<void>.delayed(Duration.zero);
    StartupLogger.mark('Deferred startup tasks started');
    await _pushNotificationService.initialize();
    StartupLogger.mark('Notification initialization finished');
    if (_backendClient.isAuthenticated) {
      unawaited(_registerDeviceForPush());
    }
    if (continuousLocationUpdates) {
      _startContinuousLocationUpdates();
    }
    StartupLogger.mark('Navigation ready');
  }

  Future<void> _refreshSessionBeforeFirstScreen() async {
    StartupLogger.mark('Initial API refresh started');
    try {
      if (house == null) {
        final payload = await _backendClient.getCurrentUser();
        _applyAuthPayload(payload);
      } else {
        await _refreshActiveHouseSections(
          awaitSections: false,
          setLoading: members.isEmpty &&
              alerts.isEmpty &&
              reminders.isEmpty &&
              shortcuts.isEmpty,
        );
      }
      await _saveSession();
      StartupLogger.mark('Initial API refresh finished');
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
        StartupLogger.mark('Initial API refresh rejected session');
      } else {
        StartupLogger.mark('Initial API refresh failed');
      }
    } catch (_) {
      StartupLogger.mark('Initial API refresh failed');
    }
  }

  Future<void> _refreshSessionAfterFirstFrame() async {
    await Future<void>.delayed(Duration.zero);
    StartupLogger.mark('Authentication check/API refresh started');
    try {
      if (house == null) {
        final payload = await _backendClient.getCurrentUser();
        _applyAuthPayload(payload);
        await _saveSession();
      } else {
        await _refreshActiveHouseSections(
          awaitSections: false,
          setLoading: false,
        );
        await _saveSession();
      }
      StartupLogger.mark('Authentication check/API refresh finished');
      notifyListeners();
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
        StartupLogger.mark('Authentication rejected; session cleared');
        notifyListeners();
      }
    } catch (_) {
      StartupLogger.mark('Authentication check/API refresh failed');
      // Keep the saved session during temporary network outages.
    }
  }

  AppUser? memberById(String id) {
    for (final member in members) {
      if (member.id == id) return member;
    }
    return null;
  }

  Future<bool> registerUser({
    required String name,
    String? email,
    String? phone,
    String? password,
    bool childMode = false,
  }) async {
    return _run(() async {
      final payload = await _backendClient.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        childMode: childMode,
      );
      _applyAuthPayload(payload);
      await _saveSession();
      unawaited(
          HoomyAnalyticsService.instance.setSignedInUser(currentUser?.id));
      unawaited(HoomyAnalyticsService.instance.logEvent('sign_up', parameters: {
        'method': childMode
            ? 'child'
            : email != null
                ? 'email'
                : 'phone',
      }));
      unawaited(_registerDeviceForPush());
    });
  }

  Future<bool> loginUser({
    String? email,
    String? phone,
    String? childName,
    String? password,
  }) async {
    return _run(() async {
      final payload = await _backendClient.login(
        email: email,
        phone: phone,
        childName: childName,
        password: password,
      );
      _applyAuthPayload(payload);
      await _saveSession();
      unawaited(
          HoomyAnalyticsService.instance.setSignedInUser(currentUser?.id));
      unawaited(HoomyAnalyticsService.instance.logEvent('login', parameters: {
        'method': childName != null
            ? 'child'
            : email != null
                ? 'email'
                : 'phone',
      }));
      unawaited(_registerDeviceForPush());
    });
  }

  Future<bool> requestPasswordReset({String? email, String? phone}) async {
    return _run(() async {
      await _backendClient.requestPasswordReset(email: email, phone: phone);
    });
  }

  Future<bool> resetPassword(
      {String? email, String? phone, required String newPassword}) async {
    return _run(() async {
      await _backendClient.resetPassword(
          email: email, phone: phone, newPassword: newPassword);
    });
  }

  Future<AppUpdateInfo> checkForUpdate() async {
    final payload = await _backendClient.getAppUpdate(
      currentVersion: AppConfig.appVersion,
    );
    return AppUpdateInfo.fromJson(
      payload,
      currentVersion: AppConfig.appVersion,
    );
  }

  Future<bool> createHouse({
    required String name,
    required String address,
    GeoPoint? location,
    required String relation,
    bool markOutside = false,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    return _run(() async {
      final payload = await _backendClient.createHouse(
        name: name,
        address: address,
        role: relation,
        location: location == null
            ? null
            : {'lat': location.lat, 'lng': location.lng},
      );
      _applyHouseState(payload);
      if (markOutside && house != null) {
        final statusPayload = await _backendClient.updateMyLocationStatus(
          houseId: house!.id,
          outsideHouse: true,
        );
        _applyMemberStatusPayload(statusPayload, fallbackRelation: relation);
      }
      currentUser = (currentUser ?? user).copyWith(
        relation: relation,
        outsideHouse: markOutside
            ? true
            : location == null
                ? user.outsideHouse
                : false,
      );
      _upsertMember(currentUser!);
      await _saveSession();
      unawaited(
          HoomyAnalyticsService.instance.logEvent('house_created', parameters: {
        'has_location': location != null,
        'marked_outside': markOutside,
      }));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> joinHouse({
    required String houseCode,
    required String relation,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    return _run(() async {
      final payload = await _backendClient.joinHouse(
        houseCode: houseCode,
        relation: relation,
      );
      _applyHouseState(payload);
      currentUser = (memberById(user.id) ?? user).copyWith(relation: relation);
      await _saveSession();
      unawaited(HoomyAnalyticsService.instance.logEvent('house_joined'));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> changeHouse({
    required String houseCode,
    required String relation,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    return _run(() async {
      final payload = await _backendClient.joinHouse(
        houseCode: houseCode,
        relation: relation,
      );
      _applyHouseState(payload);

      final activeHouseId = house?.id;
      if (activeHouseId != null) {
        final statusPayload = await _backendClient.updateMyLocationStatus(
          houseId: activeHouseId,
          outsideHouse: true,
        );
        _applyMemberStatusPayload(statusPayload, fallbackRelation: relation);
      } else {
        currentUser = (memberById(user.id) ?? user).copyWith(
          relation: relation,
          outsideHouse: true,
        );
        _upsertMember(currentUser!);
      }
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> selectHouse(House selectedHouse,
      {bool markOutside = false}) async {
    selectingHouseId = selectedHouse.id;
    notifyListeners();
    try {
      return await _run(() async {
        final payload = await _backendClient.getHouseSummary(selectedHouse.id);
        _applyHouseSummary(payload);
        _setHouseSectionsLoading(true);
        if (markOutside && house?.id != null) {
          final relation = currentUser?.relation ?? 'Member';
          final statusPayload = await _backendClient.updateMyLocationStatus(
            houseId: house!.id,
            outsideHouse: true,
          );
          _applyMemberStatusPayload(statusPayload, fallbackRelation: relation);
        }
        await _saveSession();
        unawaited(_loadHouseSections(selectedHouse.id));
      }, clearSessionOnUnauthorized: true);
    } finally {
      selectingHouseId = null;
      notifyListeners();
    }
  }

  Future<bool> refreshHouseState({
    bool silent = false,
  }) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    if (silent) {
      try {
        await _refreshActiveHouseSections(
          awaitSections: true,
          setLoading: false,
        );
        return true;
      } catch (_) {
        return false;
      }
    }

    return _run(() async {
      await _refreshActiveHouseSections(
        awaitSections: true,
        setLoading: true,
      );
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> updateHouseLocation(GeoPoint location) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.updateHouseLocation(
        houseId: houseId,
        location: {'lat': location.lat, 'lng': location.lng},
        address: _locationAddress(location),
      );
      _applyHouseState(payload);
      await updateCurrentLocationStatus(location);
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> addMember(AppUser user) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.addMember(
        houseId: houseId,
        name: user.name,
        relation: user.relation,
        email: user.email,
        phone: user.phone,
        childMode: user.childMode,
      );
      _applyHouseState(payload);
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> addAlert(NeedAlert alert) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.createAlert(
        houseId: houseId,
        title: alert.title,
        note: alert.note,
        quantity: alert.quantity,
        emergency: alert.emergency,
        targetMemberIds: alert.targetMemberIds,
      );
      final savedAlert = _parseAlert(payload);
      _upsertAlert(savedAlert);
      _notifyForAlertIfNeeded(savedAlert);
      unawaited(HoomyAnalyticsService.instance
          .logEvent('need_alert_created', parameters: {
        'emergency': savedAlert.emergency,
        'selected_member_count': savedAlert.targetMemberIds.length,
        'has_quantity': savedAlert.quantity.isNotEmpty,
        'has_note': savedAlert.note.isNotEmpty,
      }));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> markAlertBought(NeedAlert alert,
      {String? quantity, String? price}) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.markAlertBought(
        houseId: houseId,
        alertId: alert.id,
        quantity: quantity,
        price: price,
      );
      _upsertAlert(_parseAlert(payload));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> markAlertsBought(List<NeedAlert> selectedAlerts) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null || selectedAlerts.isEmpty) {
      return false;
    }

    return _run(() async {
      for (final alert in selectedAlerts) {
        final payload = await _backendClient.markAlertBought(
          houseId: houseId,
          alertId: alert.id,
        );
        _upsertAlert(_parseAlert(payload));
      }
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> deleteAlert(NeedAlert alert) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null || alert.createdBy != user.id) {
      return false;
    }

    return _run(() async {
      await _backendClient.deleteAlert(houseId: houseId, alertId: alert.id);
      alerts.removeWhere((item) => item.id == alert.id);
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final user = currentUser;
    if (user == null) return false;

    return _run(() async {
      final payload = await _backendClient.updateNotificationPreferences(
        needAlerts: preferences.needAlerts,
        emergencyAlerts: preferences.emergencyAlerts,
        chatMessages: preferences.chatMessages,
      );
      if (payload['user'] is Map<String, dynamic>) {
        currentUser = _parseUser(payload['user'] as Map<String, dynamic>);
      } else {
        currentUser = user.copyWith(notificationPreferences: preferences);
      }
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> updateMyBirthDate(DateTime? birthDate) async {
    return updateMyProfile(birthDate: birthDate);
  }

  Future<bool> updateMyProfile({
    String? name,
    Object? phone = _profileBirthDateUnchanged,
    Object? birthDate = _profileBirthDateUnchanged,
  }) async {
    final user = currentUser;
    if (user == null) return false;
    final phoneChanged = !identical(phone, _profileBirthDateUnchanged);
    final birthdayChanged = !identical(birthDate, _profileBirthDateUnchanged);
    final nextBirthDate =
        birthdayChanged ? birthDate as DateTime? : user.birthDate;

    return _run(() async {
      final payload = birthdayChanged && phoneChanged
          ? await _backendClient.updateProfile(
              name: name,
              phone: phone,
              birthDate: nextBirthDate?.toIso8601String(),
            )
          : birthdayChanged
              ? await _backendClient.updateProfile(
                  name: name,
                  birthDate: nextBirthDate?.toIso8601String(),
                )
              : phoneChanged
                  ? await _backendClient.updateProfile(
                      name: name,
                      phone: phone,
                    )
                  : await _backendClient.updateProfile(name: name);
      if (payload['user'] is Map<String, dynamic>) {
        currentUser = _parseUser(payload['user'] as Map<String, dynamic>);
      } else {
        currentUser = phoneChanged
            ? user.copyWith(
                name: name,
                phone: phone,
                birthDate: nextBirthDate,
              )
            : user.copyWith(
                name: name,
                birthDate: nextBirthDate,
              );
      }
      _upsertMember(currentUser!);
      if (birthdayChanged) {
        await _syncMyBirthdayReminder(currentUser!, nextBirthDate);
      }
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> addReminder(FamilyReminder reminder) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.createReminder(
        houseId: houseId,
        title: reminder.title,
        note: reminder.note,
        dueAt: reminder.dueAt.toIso8601String(),
        ringTimes: reminder.ringTimes,
        recurrence: reminder.recurrence,
        recurrenceWeekdays: reminder.recurrenceWeekdays,
        isBirthday: reminder.isBirthday,
        birthdayMemberId: reminder.birthdayMemberId,
      );
      final savedReminder =
          _withFallbackBirthdayMetadata(_parseReminder(payload), reminder);
      _upsertReminder(savedReminder);
      unawaited(_alertNotificationService.scheduleReminder(savedReminder));
      unawaited(HoomyAnalyticsService.instance
          .logEvent('reminder_updated', parameters: {
        'ring_time_count': savedReminder.effectiveRingTimes.length,
        'is_birthday': savedReminder.isBirthday,
      }));
      unawaited(HoomyAnalyticsService.instance
          .logEvent('reminder_created', parameters: {
        'ring_time_count': savedReminder.effectiveRingTimes.length,
        'is_birthday': savedReminder.isBirthday,
        'has_note': savedReminder.note.isNotEmpty,
      }));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> updateReminder(FamilyReminder reminder) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.updateReminder(
        houseId: houseId,
        reminderId: reminder.id,
        title: reminder.title,
        note: reminder.note,
        dueAt: reminder.dueAt.toIso8601String(),
        ringTimes: reminder.ringTimes,
        recurrence: reminder.recurrence,
        recurrenceWeekdays: reminder.recurrenceWeekdays,
        isBirthday: reminder.isBirthday,
        birthdayMemberId: reminder.birthdayMemberId,
      );
      final savedReminder =
          _withFallbackBirthdayMetadata(_parseReminder(payload), reminder);
      _upsertReminder(savedReminder);
      unawaited(_alertNotificationService.scheduleReminder(savedReminder));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> deleteReminder(FamilyReminder reminder) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      await _backendClient.deleteReminder(
          houseId: houseId, reminderId: reminder.id);
      reminders.removeWhere((item) => item.id == reminder.id);
      unawaited(_alertNotificationService.cancelReminder(reminder.id));
      unawaited(HoomyAnalyticsService.instance.logEvent('reminder_deleted'));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> sendMessage(String text, {ChatMessage? replyTo}) async {
    final user = currentUser;
    final houseId = house?.id;
    final trimmed = text.trim();
    if (user == null || houseId == null || trimmed.isEmpty) return false;

    final pendingMessage = ChatMessage(
      id: nextId('pending-message-'),
      senderId: user.id,
      text: trimmed,
      createdAt: DateTime.now(),
      pending: true,
      replyToMessageId: replyTo?.id,
      replyToSenderId: replyTo?.senderId,
      replyToText: replyTo?.text,
    );
    messages.insert(0, pendingMessage);
    errorMessage = null;
    notifyListeners();
    unawaited(_alertNotificationService.playMessageSendCue());

    try {
      final payload = await _backendClient.sendMessage(
        houseId: houseId,
        text: trimmed,
        replyToMessageId: replyTo?.id,
      );
      final savedMessage = _parseMessage(payload);
      messages.removeWhere((item) => item.id == pendingMessage.id);
      _upsertMessage(savedMessage);
      notifyListeners();
      return true;
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
        _markMessageFailed(pendingMessage.id);
      }
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Could not connect to the Hoomy backend.';
      _markMessageFailed(pendingMessage.id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendVoiceMessage({
    required String audioBase64,
    required String audioMimeType,
    required int durationSeconds,
    ChatMessage? replyTo,
  }) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null || audioBase64.isEmpty) return false;

    final pendingMessage = ChatMessage(
      id: nextId('pending-message-'),
      senderId: user.id,
      text: 'Voice message',
      createdAt: DateTime.now(),
      pending: true,
      replyToMessageId: replyTo?.id,
      replyToSenderId: replyTo?.senderId,
      replyToText: replyTo?.text,
      audio: true,
      audioBase64: audioBase64,
      audioMimeType: audioMimeType,
      audioDurationSeconds: durationSeconds,
    );
    messages.insert(0, pendingMessage);
    errorMessage = null;
    notifyListeners();
    unawaited(_alertNotificationService.playMessageSendCue());

    try {
      final payload = await _backendClient.sendMessage(
        houseId: houseId,
        text: 'Voice message',
        replyToMessageId: replyTo?.id,
        audio: true,
        audioBase64: audioBase64,
        audioMimeType: audioMimeType,
        audioDurationSeconds: durationSeconds,
      );
      final savedMessage = _parseMessage(payload);
      messages.removeWhere((item) => item.id == pendingMessage.id);
      _upsertMessage(savedMessage);
      notifyListeners();
      return true;
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
        _markMessageFailed(pendingMessage.id);
      }
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Could not connect to the Hoomy backend.';
      _markMessageFailed(pendingMessage.id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendImageMessage({
    required String imageBase64,
    required String imageMimeType,
    ChatMessage? replyTo,
  }) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null || imageBase64.isEmpty) return false;

    final pendingMessage = ChatMessage(
      id: nextId('pending-message-'),
      senderId: user.id,
      text: 'Photo',
      createdAt: DateTime.now(),
      pending: true,
      replyToMessageId: replyTo?.id,
      replyToSenderId: replyTo?.senderId,
      replyToText: replyTo?.text,
      image: true,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );
    messages.insert(0, pendingMessage);
    errorMessage = null;
    notifyListeners();
    unawaited(_alertNotificationService.playMessageSendCue());

    try {
      final payload = await _backendClient.sendMessage(
        houseId: houseId,
        text: 'Photo',
        replyToMessageId: replyTo?.id,
        image: true,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
      final savedMessage = _parseMessage(payload);
      messages.removeWhere((item) => item.id == pendingMessage.id);
      _upsertMessage(savedMessage);
      notifyListeners();
      return true;
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
        _markMessageFailed(pendingMessage.id);
      }
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Could not connect to the Hoomy backend.';
      _markMessageFailed(pendingMessage.id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> editMessage(ChatMessage message, String text) async {
    final user = currentUser;
    final houseId = house?.id;
    final trimmed = text.trim();
    if (user == null ||
        houseId == null ||
        trimmed.isEmpty ||
        message.senderId != user.id ||
        message.system ||
        message.pending) {
      return false;
    }

    final index = messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return false;
    final previous = messages[index];
    messages[index] = previous.copyWith(
      text: trimmed,
      edited: true,
      editedAt: DateTime.now(),
    );
    errorMessage = null;
    notifyListeners();

    try {
      final payload = await _backendClient.editMessage(
        houseId: houseId,
        messageId: message.id,
        text: trimmed,
      );
      _upsertMessage(_parseMessage(payload));
      notifyListeners();
      return true;
    } on HoomyBackendException catch (error) {
      messages[index] = previous;
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
      }
      notifyListeners();
      return false;
    } catch (_) {
      messages[index] = previous;
      errorMessage = 'Could not connect to the Hoomy backend.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> reactToMessage(ChatMessage message, String emoji) async {
    final user = currentUser;
    final houseId = house?.id;
    if (user == null || houseId == null || message.pending) return false;

    final index = messages.indexWhere((item) => item.id == message.id);
    if (index == -1) return false;
    final previous = messages[index];
    ChatMessageReaction? currentReaction;
    for (final reaction in previous.reactions) {
      if (reaction.userId == user.id) {
        currentReaction = reaction;
        break;
      }
    }
    final nextEmoji = currentReaction?.emoji == emoji ? null : emoji;
    final nextReactions = previous.reactions
        .where((reaction) => reaction.userId != user.id)
        .toList();
    if (nextEmoji != null) {
      nextReactions.add(ChatMessageReaction(
        userId: user.id,
        emoji: nextEmoji,
        reactedAt: DateTime.now(),
      ));
    }

    messages[index] = previous.copyWith(reactions: nextReactions);
    errorMessage = null;
    notifyListeners();

    try {
      final payload = await _backendClient.reactToMessage(
        houseId: houseId,
        messageId: message.id,
        emoji: nextEmoji,
      );
      _upsertMessage(_parseMessage(payload));
      notifyListeners();
      return true;
    } on HoomyBackendException catch (error) {
      messages[index] = previous;
      if (error.statusCode == 401) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
      }
      notifyListeners();
      return false;
    } catch (_) {
      messages[index] = previous;
      errorMessage = 'Could not connect to the Hoomy backend.';
      notifyListeners();
      return false;
    }
  }

  Future<void> setLanguageCode(String code) async {
    if (languageCode == code) return;
    languageCode = code;
    await _sessionStorage.saveLanguageCode(code);
    notifyListeners();
  }

  Future<bool> addShortcut(QuickShortcut shortcut) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.createShortcut(
        houseId: houseId,
        label: shortcut.label,
        actionType: shortcut.type.name,
        actionValue: shortcut.value,
      );
      _upsertShortcut(_parseShortcut(payload));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> updateShortcut(QuickShortcut shortcut) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      final payload = await _backendClient.updateShortcut(
        houseId: houseId,
        shortcutId: shortcut.id,
        label: shortcut.label,
        actionType: shortcut.type.name,
        actionValue: shortcut.value,
      );
      _upsertShortcut(_parseShortcut(payload));
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> deleteShortcut(QuickShortcut shortcut) async {
    final houseId = house?.id;
    if (houseId == null) return false;

    return _run(() async {
      await _backendClient.deleteShortcut(
          houseId: houseId, shortcutId: shortcut.id);
      shortcuts.removeWhere((item) => item.id == shortcut.id);
    }, clearSessionOnUnauthorized: true);
  }

  Future<void> signOut() async {
    _stopContinuousLocationUpdates();
    await _clearSession();
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> updateCurrentLocationStatus(GeoPoint currentLocation,
      {bool silent = false}) async {
    final houseId = house?.id;
    final houseLocation = house?.location;
    final user = currentUser;
    if (houseId == null || houseLocation == null || user == null) return false;

    final outsideHouse = _distanceMeters(houseLocation, currentLocation) > 150;
    if (silent) {
      try {
        final payload = await _backendClient.updateMyLocationStatus(
          houseId: houseId,
          outsideHouse: outsideHouse,
          location: {'lat': currentLocation.lat, 'lng': currentLocation.lng},
        );
        _applyMemberStatusPayload(payload, fallbackRelation: user.relation);
        await _saveSession();
        notifyListeners();
        return true;
      } catch (_) {
        return false;
      }
    }

    return _run(() async {
      final payload = await _backendClient.updateMyLocationStatus(
        houseId: houseId,
        outsideHouse: outsideHouse,
        location: {'lat': currentLocation.lat, 'lng': currentLocation.lng},
      );
      _applyMemberStatusPayload(payload, fallbackRelation: user.relation);
      await _saveSession();
    }, clearSessionOnUnauthorized: true);
  }

  Future<bool> refreshCurrentLocationStatusFromDevice(
      {bool silent = false}) async {
    if (house?.location == null || currentUser == null) return false;
    final enabled = await _locationService.isLocationServiceEnabled();
    if (!enabled) return false;
    final location = await _locationService.requestCurrentLocation();
    if (location == null) return false;
    return updateCurrentLocationStatus(location, silent: silent);
  }

  Future<bool> setContinuousLocationUpdates(bool enabled) async {
    continuousLocationUpdates = enabled;
    await _sessionStorage.saveContinuousLocationUpdates(enabled);
    if (enabled) {
      _startContinuousLocationUpdates();
      final updated = await refreshCurrentLocationStatusFromDevice();
      notifyListeners();
      return updated;
    }
    _stopContinuousLocationUpdates();
    notifyListeners();
    return true;
  }

  String nextId(String prefix) =>
      '$prefix${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _stopContinuousLocationUpdates();
    unawaited(_pushTokenSubscription?.cancel());
    unawaited(_pushDiagnosticsSubscription?.cancel());
    unawaited(_remoteChatMessageSubscription?.cancel());
    unawaited(_stateRefreshRequestSubscription?.cancel());
    _backendClient.dispose();
    super.dispose();
  }

  Future<void> _registerDeviceForPush() async {
    if (!_backendClient.isAuthenticated) return;

    final token = await _pushNotificationService.currentToken();
    if (token != null) {
      try {
        await _backendClient.registerFcmToken(token);
        pushStatusMessage = 'Push token registered with backend.';
      } catch (_) {
        pushStatusMessage = 'Could not register push token with backend.';
        // Push setup should never block login or app startup.
      }
      notifyListeners();
    }

    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription =
        _pushNotificationService.tokenRefreshes.listen((token) async {
      try {
        await _backendClient.registerFcmToken(token);
        pushStatusMessage = 'Push token refreshed and registered.';
        notifyListeners();
      } catch (_) {
        pushStatusMessage = 'Could not register refreshed push token.';
        notifyListeners();
        // The token will be retried on next app start or refresh.
      }
    });
  }

  Future<bool> _run(Future<void> Function() action,
      {bool clearSessionOnUnauthorized = false}) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on HoomyBackendException catch (error) {
      if (error.statusCode == 401 && clearSessionOnUnauthorized) {
        await _clearSession();
        errorMessage = 'Session expired. Please sign in again.';
      } else {
        errorMessage = error.message;
      }
      return false;
    } catch (_) {
      errorMessage = 'Could not connect to the Hoomy backend.';
      return false;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _clearSession() async {
    await _sessionStorage.clear();
    _stopContinuousLocationUpdates();
    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription = null;
    continuousLocationUpdates = false;
    _backendClient.clearToken();
    currentUser = null;
    house = null;
    _clearHouseScopedState();
  }

  Future<void> _saveSession() async {
    final user = currentUser;
    final token = _backendClient.token;
    if (user == null || token == null) return;
    await _sessionStorage.saveSession(
      token: token,
      userJson: jsonEncode(_userToJson(user)),
      houseJson: house == null ? null : jsonEncode(_houseToJson(house!)),
      houseStateJson:
          house == null ? null : jsonEncode(_cachedHouseStateToJson()),
    );
    _printLoginToken(token);
  }

  void _printLoginToken(String token) {
    debugPrint('LOGIN_TOKEN=$token');
  }

  void _restoreCachedHouseOnly(SavedSession session) {
    if (session.houseJson == null) return;
    try {
      house =
          _parseHouse(jsonDecode(session.houseJson!) as Map<String, dynamic>);
    } catch (error) {
      debugPrint('[HoomyStartup] Cached house could not be used: $error');
      house = null;
    }
  }

  void _applyAuthPayload(Map<String, dynamic> payload) {
    currentUser = _parseUser(payload['user'] as Map<String, dynamic>);
    _applyAvailableHouses(payload);
    if (availableHouses.length > 1) {
      house = null;
      _clearHouseScopedState(clearAvailableHouses: false);
    } else if (payload['house'] is Map<String, dynamic>) {
      _applyHouseState(payload);
    } else {
      house = null;
      _clearHouseScopedState(clearAvailableHouses: false);
    }
  }

  void _clearHouseScopedState({bool clearAvailableHouses = true}) {
    members.clear();
    alerts.clear();
    messages.clear();
    reminders.clear();
    shortcuts.clear();
    if (clearAvailableHouses) availableHouses.clear();
    unreadChatMessageCount = 0;
    isChatVisible = false;
    _pushNotificationService.setChatScreenVisible(false);
    _connectedHouseId = null;
    isLoadingMembers = false;
    isLoadingAlerts = false;
    isLoadingReminders = false;
    isLoadingMessages = false;
    isLoadingOlderMessages = false;
    hasOlderMessages = true;
    isLoadingShortcuts = false;
  }

  void _setHouseSectionsLoading(bool value) {
    isLoadingMembers = value;
    isLoadingAlerts = value;
    isLoadingReminders = value;
    isLoadingShortcuts = value;
    notifyListeners();
  }

  void _applyHouseSummary(
    Map<String, dynamic> payload, {
    bool clearHouseScopedState = true,
  }) {
    house = _parseHouse(payload['house'] as Map<String, dynamic>);
    _applyAvailableHouses(payload);
    if (payload['user'] is Map<String, dynamic>) {
      currentUser = _parseUser(payload['user'] as Map<String, dynamic>);
    }
    if (clearHouseScopedState) {
      _clearHouseScopedState(clearAvailableHouses: false);
    }
    _connectSocket(house!.id);
    if (continuousLocationUpdates) {
      _startContinuousLocationUpdates();
    }
  }

  Future<void> _loadHouseSections(String houseId) async {
    final sectionLoads = <Future<void>>[
      _loadHouseMembers(houseId),
      _loadHouseAlerts(houseId),
      _loadHouseReminders(houseId),
      _loadHouseShortcuts(houseId),
    ];
    await Future.wait<void>(sectionLoads);
    await _saveSession();
  }

  Future<void> _refreshActiveHouseSections({
    required bool awaitSections,
    required bool setLoading,
  }) async {
    final activeHouseId = house?.id;
    if (activeHouseId == null) return;

    final payload = await _backendClient.getHouseSummary(activeHouseId);
    if (house?.id != activeHouseId) return;
    _applyHouseSummary(payload, clearHouseScopedState: false);
    if (setLoading) {
      _setHouseSectionsLoading(true);
    }

    final sectionsLoad = _loadHouseSections(activeHouseId);
    if (awaitSections) {
      await sectionsLoad;
    } else {
      unawaited(sectionsLoad);
    }
  }

  Future<void> _loadHouseMembers(String houseId) async {
    try {
      final payload = await _backendClient.getHouseMembers(houseId);
      if (house?.id != houseId) return;
      _applyMembersSection(payload);
    } catch (_) {
      // Keep any cached data and let manual refresh retry.
    } finally {
      if (house?.id == houseId) {
        isLoadingMembers = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadHouseAlerts(String houseId) async {
    try {
      final payload = await _backendClient.getHouseAlerts(houseId);
      if (house?.id != houseId) return;
      _applyAlertsSection(payload);
    } catch (_) {
      // Keep any cached data and let manual refresh retry.
    } finally {
      if (house?.id == houseId) {
        isLoadingAlerts = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadHouseReminders(String houseId) async {
    try {
      final payload = await _backendClient.getHouseReminders(houseId);
      if (house?.id != houseId) return;
      _applyRemindersSection(payload);
    } catch (_) {
      // Keep any cached data and let manual refresh retry.
    } finally {
      if (house?.id == houseId) {
        isLoadingReminders = false;
        notifyListeners();
      }
    }
  }

  Future<bool> refreshChatMessages() async {
    final houseId = house?.id;
    if (houseId == null || isLoadingMessages) return false;

    isLoadingMessages = true;
    notifyListeners();
    try {
      final payload = await _backendClient.getHouseMessages(
        houseId,
        limit: _messagePageSize,
      );
      if (house?.id != houseId) return false;
      _applyMessagesSection(payload);
      await _saveSession();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (house?.id == houseId) {
        isLoadingMessages = false;
        notifyListeners();
      }
    }
  }

  Future<bool> loadOlderChatMessages() async {
    final houseId = house?.id;
    if (houseId == null ||
        isLoadingMessages ||
        isLoadingOlderMessages ||
        !hasOlderMessages ||
        messages.isEmpty) {
      return false;
    }

    final oldestMessage = messages.last;
    isLoadingOlderMessages = true;
    notifyListeners();
    try {
      final payload = await _backendClient.getHouseMessages(
        houseId,
        limit: _messagePageSize,
        before: oldestMessage.createdAt.toIso8601String(),
      );
      if (house?.id != houseId) return false;
      final added = _appendOlderMessagesSection(payload);
      await _saveSession();
      return added;
    } catch (_) {
      return false;
    } finally {
      if (house?.id == houseId) {
        isLoadingOlderMessages = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadHouseShortcuts(String houseId) async {
    try {
      final payload = await _backendClient.getHouseShortcuts(houseId);
      if (house?.id != houseId) return;
      _applyShortcutsSection(payload);
    } catch (_) {
      // Keep any cached data and let manual refresh retry.
    } finally {
      if (house?.id == houseId) {
        isLoadingShortcuts = false;
        notifyListeners();
      }
    }
  }

  void _applyHouseState(Map<String, dynamic> payload) {
    isLoadingMembers = false;
    isLoadingAlerts = false;
    isLoadingReminders = false;
    isLoadingMessages = false;
    isLoadingShortcuts = false;
    final wasChatVisible = isChatVisible;
    house = _parseHouse(payload['house'] as Map<String, dynamic>);
    _applyAvailableHouses(payload);

    members
      ..clear()
      ..addAll((payload['members'] as List<dynamic>? ?? [])
          .map((item) => _parseMember(item as Map<String, dynamic>)));

    alerts
      ..clear()
      ..addAll((payload['alerts'] as List<dynamic>? ?? [])
          .map((item) => _parseAlert(item as Map<String, dynamic>)));

    reminders
      ..clear()
      ..addAll((payload['reminders'] as List<dynamic>? ?? [])
          .map((item) => _parseReminder(item as Map<String, dynamic>)));
    for (final reminder in reminders) {
      unawaited(_alertNotificationService.scheduleReminder(reminder));
    }

    final parsedMessages = _parseMessageList(payload);
    hasOlderMessages = parsedMessages.length >= _messagePageSize;
    messages
      ..clear()
      ..addAll(parsedMessages.take(_cachedMessageLimit));
    if (wasChatVisible) {
      unreadChatMessageCount = 0;
      isChatVisible = true;
      _pushNotificationService.setChatScreenVisible(true);
      _clearChatNotifications();
      unawaited(_markChatMessagesSeen());
    } else {
      unreadChatMessageCount = _unseenMessageCountForCurrentUser();
      isChatVisible = false;
    }

    shortcuts
      ..clear()
      ..addAll((payload['shortcuts'] as List<dynamic>? ?? [])
          .map((item) => _parseShortcut(item as Map<String, dynamic>)));

    final user = currentUser;
    if (user != null) {
      final member = memberById(user.id);
      if (member != null) currentUser = member;
    }

    _connectSocket(house!.id);
    if (continuousLocationUpdates) {
      _startContinuousLocationUpdates();
    }
  }

  void _applyMembersSection(Map<String, dynamic> payload) {
    members
      ..clear()
      ..addAll((payload['members'] as List<dynamic>? ?? [])
          .map((item) => _parseMember(item as Map<String, dynamic>)));
    final user = currentUser;
    if (user != null) {
      final member = memberById(user.id);
      if (member != null) currentUser = member;
    }
  }

  void _applyAlertsSection(Map<String, dynamic> payload) {
    alerts
      ..clear()
      ..addAll((payload['alerts'] as List<dynamic>? ?? [])
          .map((item) => _parseAlert(item as Map<String, dynamic>)));
  }

  void _applyRemindersSection(Map<String, dynamic> payload) {
    reminders
      ..clear()
      ..addAll((payload['reminders'] as List<dynamic>? ?? [])
          .map((item) => _parseReminder(item as Map<String, dynamic>)));
    for (final reminder in reminders) {
      unawaited(_alertNotificationService.scheduleReminder(reminder));
    }
  }

  void _applyMessagesSection(Map<String, dynamic> payload) {
    final wasChatVisible = isChatVisible;
    final parsedMessages = _parseMessageList(payload);
    hasOlderMessages = parsedMessages.length >= _messagePageSize;
    messages
      ..clear()
      ..addAll(parsedMessages);
    if (wasChatVisible) {
      unreadChatMessageCount = 0;
      isChatVisible = true;
      _pushNotificationService.setChatScreenVisible(true);
      _clearChatNotifications();
      unawaited(_markChatMessagesSeen());
    } else {
      unreadChatMessageCount = _unseenMessageCountForCurrentUser();
      isChatVisible = false;
    }
  }

  bool _appendOlderMessagesSection(Map<String, dynamic> payload) {
    final olderMessages = _parseMessageList(payload);
    var added = 0;
    final existingIds = messages.map((message) => message.id).toSet();
    for (final message in olderMessages) {
      if (existingIds.add(message.id)) {
        messages.add(message);
        added += 1;
      }
    }
    hasOlderMessages = olderMessages.length >= _messagePageSize && added > 0;
    return added > 0;
  }

  List<ChatMessage> _parseMessageList(Map<String, dynamic> payload) {
    return (payload['messages'] as List<dynamic>? ?? [])
        .map((item) => _parseMessage(item as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();
  }

  void _applyShortcutsSection(Map<String, dynamic> payload) {
    shortcuts
      ..clear()
      ..addAll((payload['shortcuts'] as List<dynamic>? ?? [])
          .map((item) => _parseShortcut(item as Map<String, dynamic>)));
  }

  void _applyAvailableHouses(Map<String, dynamic> payload) {
    final items = payload['houses'] as List<dynamic>? ?? [];
    availableHouses
      ..clear()
      ..addAll(items.map((item) => _parseHouse(item as Map<String, dynamic>)));
    final activeHouse = house;
    if (activeHouse != null &&
        !availableHouses.any((item) => item.id == activeHouse.id)) {
      availableHouses.add(activeHouse);
    }
  }

  void _connectSocket(String houseId) {
    if (_connectedHouseId == houseId) return;
    _connectedHouseId = houseId;
    _backendClient.connectSocket(
      houseId: houseId,
      onEvent: (event, data) {
        if (data is! Map) return;
        final payload = Map<String, dynamic>.from(data);
        switch (event) {
          case 'alertCreated':
            final alert = _parseAlert(payload);
            _upsertAlert(alert);
            _notifyForAlertIfNeeded(alert);
            break;
          case 'alertBought':
            _upsertAlert(_parseAlert(payload));
            unawaited(
                _refreshHouseStateFromSocket(payload['houseId']?.toString()));
            break;
          case 'alertDeleted':
            final alertId = payload['id']?.toString();
            if (alertId == null) break;
            alerts.removeWhere((item) => item.id == alertId);
            break;
          case 'reminderCreated':
            final reminder = _parseReminder(payload);
            _upsertReminder(reminder);
            unawaited(_alertNotificationService.scheduleReminder(reminder));
            if (reminder.createdBy != currentUser?.id) {
              unawaited(_alertNotificationService.showReminder(reminder));
            }
            break;
          case 'reminderUpdated':
            final reminder = _parseReminder(payload);
            _upsertReminder(reminder);
            unawaited(_alertNotificationService.scheduleReminder(reminder));
            break;
          case 'reminderDeleted':
            final reminderId = payload['id']?.toString();
            if (reminderId == null) break;
            reminders.removeWhere((item) => item.id == reminderId);
            unawaited(_alertNotificationService.cancelReminder(reminderId));
            break;
          case 'messageCreated':
            final message = _parseMessage(payload);
            _handleIncomingChatMessage(
              message,
              showLocalNotification: true,
            );
            break;
          case 'messageUpdated':
            _upsertMessage(_parseMessage(payload));
            notifyListeners();
            break;
          case 'shortcutCreated':
          case 'shortcutUpdated':
            if (payload['createdBy']?.toString() != currentUser?.id) break;
            _upsertShortcut(_parseShortcut(payload));
            break;
          case 'shortcutDeleted':
            if (payload['createdBy']?.toString() != currentUser?.id) break;
            shortcuts
                .removeWhere((item) => item.id == payload['id']?.toString());
            break;
          case 'memberAdded':
          case 'memberUpdated':
            if (payload['user'] is Map) {
              final member =
                  _parseUser(Map<String, dynamic>.from(payload['user'] as Map))
                      .copyWith(
                relation: (payload['relation'] ?? 'Member').toString(),
              );
              _upsertMember(member);
            }
            unawaited(
                _refreshHouseStateFromSocket(payload['houseId']?.toString()));
            break;
        }
        notifyListeners();
      },
    );
  }

  Future<void> _refreshHouseStateFromSocket(String? eventHouseId) async {
    final activeHouseId = house?.id;
    if (activeHouseId == null) return;
    if (eventHouseId != null &&
        eventHouseId.isNotEmpty &&
        eventHouseId != activeHouseId) {
      return;
    }

    try {
      await _refreshActiveHouseSections(
        awaitSections: true,
        setLoading: false,
      );
    } catch (_) {
      // Realtime refresh will be retried by the next app sync or socket event.
    }
  }

  void _handleIncomingChatMessage(
    ChatMessage message, {
    bool showLocalNotification = false,
  }) {
    final isNewMessage = _upsertMessage(message);
    if (!isNewMessage) return;
    if (message.senderId != currentUser?.id) {
      unawaited(_markMessageReceived(message));
    }

    if (!isChatVisible) {
      unreadChatMessageCount += 1;
      if (showLocalNotification &&
          message.senderId != currentUser?.id &&
          currentUser?.notificationPreferences.chatMessages != false) {
        unawaited(_alertNotificationService.showChatMessage(
          message,
          senderName: memberById(message.senderId)?.name,
        ));
      }
    } else if (message.senderId != currentUser?.id) {
      unawaited(_alertNotificationService.playMessageReceiveCue());
    }
    final lowerText = message.text.toLowerCase();
    if (message.system &&
        (lowerText.contains('bought') || lowerText.contains('done'))) {
      unawaited(refreshHouseState(silent: true));
    }
    notifyListeners();
  }

  void _notifyForAlertIfNeeded(NeedAlert alert) {
    final userId = currentUser?.id;
    if (userId == null) return;
    final preferences = currentUser?.notificationPreferences;
    if (alert.emergency) {
      if (preferences?.emergencyAlerts == false) return;
    } else if (preferences?.needAlerts == false) {
      return;
    }
    final targetsCurrentUser =
        alert.targetMemberIds.isEmpty || alert.targetMemberIds.contains(userId);
    final creatorSelectedSelf =
        alert.createdBy == userId && alert.targetMemberIds.contains(userId);
    if (alert.createdBy == userId && !creatorSelectedSelf) return;
    if (!targetsCurrentUser || !_notifiedAlertIds.add(alert.id)) return;
    unawaited(_alertNotificationService.showNeedAlert(alert));
  }

  Future<void> _markMessageReceived(ChatMessage message) async {
    final houseId = house?.id;
    final userId = currentUser?.id;
    if (houseId == null || userId == null || message.senderId == userId) return;
    try {
      final payload = await _backendClient.markMessageReceived(
        houseId: houseId,
        messageId: message.id,
      );
      _upsertMessage(_parseMessage(payload));
      notifyListeners();
    } catch (_) {
      // The next socket/state refresh can retry delivery metadata.
    }
  }

  Future<void> _markChatMessagesSeen() async {
    final houseId = house?.id;
    final userId = currentUser?.id;
    if (houseId == null || userId == null) return;
    if (!messages.any((message) =>
        message.senderId != userId && !message.seenBy.contains(userId))) {
      return;
    }
    try {
      final payload = await _backendClient.markMessagesSeen(houseId: houseId);
      final updated = payload['messages'];
      if (updated is List) {
        for (final item in updated) {
          if (item is Map) {
            _upsertMessage(_parseMessage(Map<String, dynamic>.from(item)));
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // Seen status is best-effort and will be retried when chat opens again.
    }
  }

  void _startContinuousLocationUpdates() {
    _stopContinuousLocationUpdates();
    if (house?.location == null || currentUser == null) return;
    _locationUpdateTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => refreshCurrentLocationStatusFromDevice(silent: true),
    );
  }

  void _stopContinuousLocationUpdates() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
  }

  void _applyMemberStatusPayload(Map<String, dynamic> payload,
      {required String fallbackRelation}) {
    if (payload['user'] is! Map) return;
    final updated = _parseUser(
      Map<String, dynamic>.from(payload['user'] as Map),
    ).copyWith(
      relation: (payload['relation'] ?? fallbackRelation).toString(),
    );
    currentUser = updated;
    _upsertMember(updated);
  }

  void _upsertMember(AppUser member) {
    final index = members.indexWhere((item) => item.id == member.id);
    if (index == -1) {
      members.add(member);
    } else {
      members[index] = member;
    }
  }

  void _upsertAlert(NeedAlert alert) {
    final index = alerts.indexWhere((item) => item.id == alert.id);
    if (index == -1) {
      alerts.insert(0, alert);
    } else {
      alerts[index] = alert;
    }
  }

  void _upsertReminder(FamilyReminder reminder) {
    final index = reminders.indexWhere((item) => item.id == reminder.id);
    if (index == -1) {
      reminders.insert(0, reminder);
    } else {
      reminders[index] = reminder;
    }
  }

  FamilyReminder _withFallbackBirthdayMetadata(
    FamilyReminder saved,
    FamilyReminder fallback,
  ) {
    if (saved.isBirthday || !fallback.isBirthday) return saved;
    return FamilyReminder(
      id: saved.id,
      title: saved.title,
      note: saved.note,
      dueAt: saved.dueAt,
      ringTimes: saved.ringTimes.isEmpty ? fallback.ringTimes : saved.ringTimes,
      recurrence: saved.recurrence == ReminderRecurrence.once
          ? fallback.recurrence
          : saved.recurrence,
      recurrenceWeekdays: saved.recurrenceWeekdays.isEmpty
          ? fallback.recurrenceWeekdays
          : saved.recurrenceWeekdays,
      createdBy: saved.createdBy,
      isBirthday: true,
      birthdayMemberId: fallback.birthdayMemberId,
    );
  }

  Future<void> _syncMyBirthdayReminder(
    AppUser user,
    DateTime? birthDate,
  ) async {
    final houseId = house?.id;
    if (houseId == null || birthDate == null) return;

    final existing = _birthdayReminderForUser(user.id);
    final reminder = FamilyReminder(
      id: existing?.id ?? nextId('r'),
      title: '${user.name} birthday',
      note: 'Birthday reminder for ${user.name}.',
      dueAt: _nextBirthdayOccurrence(birthDate),
      ringTimes: const ['09:00'],
      recurrence: ReminderRecurrence.once,
      createdBy: existing?.createdBy ?? user.id,
      isBirthday: true,
      birthdayMemberId: user.id,
    );

    if (existing == null) {
      final payload = await _backendClient.createReminder(
        houseId: houseId,
        title: reminder.title,
        note: reminder.note,
        dueAt: reminder.dueAt.toIso8601String(),
        ringTimes: reminder.ringTimes,
        isBirthday: true,
        birthdayMemberId: user.id,
      );
      _upsertReminder(
          _withFallbackBirthdayMetadata(_parseReminder(payload), reminder));
    } else {
      final payload = await _backendClient.updateReminder(
        houseId: houseId,
        reminderId: existing.id,
        title: reminder.title,
        note: reminder.note,
        dueAt: reminder.dueAt.toIso8601String(),
        ringTimes: reminder.ringTimes,
        isBirthday: true,
        birthdayMemberId: user.id,
      );
      _upsertReminder(
          _withFallbackBirthdayMetadata(_parseReminder(payload), reminder));
    }
  }

  DateTime _nextBirthdayOccurrence(DateTime birthDate) {
    final now = DateTime.now();
    var occurrence = DateTime(now.year, birthDate.month, birthDate.day, 9);
    if (occurrence.isBefore(DateTime(now.year, now.month, now.day))) {
      occurrence = DateTime(now.year + 1, birthDate.month, birthDate.day, 9);
    }
    return occurrence;
  }

  FamilyReminder? _birthdayReminderForUser(String userId) {
    for (final reminder in reminders) {
      if (reminder.isBirthday && reminder.birthdayMemberId == userId) {
        return reminder;
      }
    }
    return null;
  }

  bool _upsertMessage(ChatMessage message) {
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      messages.insert(0, message);
      return true;
    } else {
      messages[index] = message;
      return false;
    }
  }

  bool _isJwtExpired(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      return !expiresAt.isAfter(DateTime.now().toUtc());
    } catch (_) {
      return false;
    }
  }

  int _unseenMessageCountForCurrentUser() {
    final userId = currentUser?.id;
    if (userId == null) return 0;
    return messages
        .where((message) =>
            message.senderId != userId && !message.seenBy.contains(userId))
        .length;
  }

  void _markMessageFailed(String messageId) {
    final index = messages.indexWhere((item) => item.id == messageId);
    if (index == -1) return;
    messages[index] = messages[index].copyWith(pending: false, failed: true);
  }

  void markChatSeen() {
    if (unreadChatMessageCount == 0) return;
    unreadChatMessageCount = 0;
    _clearChatNotifications();
    notifyListeners();
  }

  void _clearChatNotifications() {
    unawaited(_alertNotificationService.clearChatMessages(
      messageIds: messages.map((message) => message.id),
    ));
  }

  void setChatVisible(bool visible) {
    if (isChatVisible == visible) {
      if (visible) {
        unreadChatMessageCount = 0;
        _clearChatNotifications();
        unawaited(_markChatMessagesSeen());
        notifyListeners();
      }
      return;
    }
    isChatVisible = visible;
    _pushNotificationService.setChatScreenVisible(visible);
    if (visible) {
      unreadChatMessageCount = 0;
      _clearChatNotifications();
      unawaited(_markChatMessagesSeen());
    }
    notifyListeners();
  }

  void _upsertShortcut(QuickShortcut shortcut) {
    final index = shortcuts.indexWhere((item) => item.id == shortcut.id);
    if (index == -1) {
      shortcuts.add(shortcut);
    } else {
      shortcuts[index] = shortcut;
    }
  }

  AppUser _parseMember(Map<String, dynamic> value) {
    final user = value['user'] as Map<String, dynamic>? ?? value;
    return _parseUser(user).copyWith(
      relation:
          (value['relation'] ?? value['role'] ?? user['relation'] ?? 'Member')
              .toString(),
    );
  }

  AppUser _parseUser(Map<String, dynamic> value) {
    final preferences =
        value['notificationPreferences'] as Map<String, dynamic>?;
    final lastLocation = value['lastLocation'] as Map<String, dynamic>?;
    return AppUser(
      id: value['id'].toString(),
      name: (value['name'] ?? 'Member').toString(),
      email: value['email']?.toString(),
      phone: value['phone']?.toString(),
      childMode: value['childMode'] == true,
      relation: (value['relation'] ?? 'Member').toString(),
      outsideHouse: value['outsideHouse'] != false,
      birthDate: _parseOptionalDate(value['birthDate']),
      lastLocation: lastLocation == null
          ? null
          : GeoPoint((lastLocation['lat'] as num).toDouble(),
              (lastLocation['lng'] as num).toDouble()),
      locationStatusUpdatedAt:
          _parseOptionalDate(value['locationStatusUpdatedAt']),
      notificationPreferences: NotificationPreferences(
        needAlerts: preferences?['needAlerts'] != false,
        emergencyAlerts: preferences?['emergencyAlerts'] != false,
        chatMessages: preferences?['chatMessages'] != false,
      ),
    );
  }

  House _parseHouse(Map<String, dynamic> value) {
    final location = value['location'] as Map<String, dynamic>?;
    return House(
      id: value['id'].toString(),
      name: (value['name'] ?? 'House').toString(),
      address: (value['address'] ?? '').toString(),
      createdBy: (value['createdBy'] ?? '').toString(),
      specialNumber: value['specialNumber']?.toString(),
      location: location == null
          ? null
          : GeoPoint((location['lat'] as num).toDouble(),
              (location['lng'] as num).toDouble()),
    );
  }

  NeedAlert _parseAlert(Map<String, dynamic> value) {
    final bought = value['bought'] as Map<String, dynamic>?;
    return NeedAlert(
      id: value['id'].toString(),
      title: (value['title'] ?? 'Need').toString(),
      note: (value['note'] ?? '').toString(),
      emergency: value['emergency'] == true,
      quantity: (value['quantity'] ?? '').toString(),
      targetMemberIds: (value['targetMemberIds'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      createdBy: (value['createdBy'] ?? '').toString(),
      createdAt: _parseDate(value['createdAt']),
      status:
          value['status'] == 'bought' ? AlertStatus.bought : AlertStatus.open,
      boughtBy: bought?['by']?.toString(),
      boughtQuantity: bought?['quantity']?.toString(),
      boughtPrice: bought?['price']?.toString(),
      boughtAt: bought == null ? null : _parseDate(bought['at']),
    );
  }

  FamilyReminder _parseReminder(Map<String, dynamic> value) {
    return FamilyReminder(
      id: value['id'].toString(),
      title: (value['title'] ?? 'Reminder').toString(),
      note: (value['note'] ?? '').toString(),
      dueAt: _parseDate(value['dueAt']),
      ringTimes: _parseRingTimes(value['ringTimes'], value['dueAt']),
      recurrence: ReminderRecurrence.normalize(value['recurrence']),
      recurrenceWeekdays: _parseWeekdays(value['recurrenceWeekdays']),
      createdBy: (value['createdBy'] ?? '').toString(),
      isBirthday: value['isBirthday'] == true,
      birthdayMemberId: value['birthdayMemberId']?.toString(),
    );
  }

  List<String> _parseRingTimes(Object? value, Object? fallbackDueAt) {
    final values = value is List ? value : const [];
    final normalized = <String>{};
    for (final item in values) {
      final normalizedTime = _normalizeRingTime(item?.toString());
      if (normalizedTime != null) normalized.add(normalizedTime);
    }
    if (normalized.isEmpty && fallbackDueAt != null) {
      final dueAt = _parseDate(fallbackDueAt);
      normalized.add(
          '${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}');
    }
    final sorted = normalized.toList()
      ..sort((a, b) => _ringTimeMinutes(a).compareTo(_ringTimeMinutes(b)));
    return sorted;
  }

  List<int> _parseWeekdays(Object? value) {
    final values = value is List ? value : const [];
    final normalized = <int>{};
    for (final item in values) {
      final day = int.tryParse(item?.toString() ?? '');
      if (day != null && day >= DateTime.monday && day <= DateTime.sunday) {
        normalized.add(day);
      }
    }
    final sorted = normalized.toList()..sort();
    return sorted;
  }

  String? _normalizeRingTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  int _ringTimeMinutes(String value) {
    final parts = value.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  ChatMessage _parseMessage(Map<String, dynamic> value) {
    return ChatMessage(
      id: value['id'].toString(),
      senderId: (value['senderId'] ?? '').toString(),
      text: (value['text'] ?? '').toString(),
      createdAt: _parseDate(value['createdAt']),
      system: value['system'] == true,
      receivedBy: (value['receivedBy'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      seenBy: (value['seenBy'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
      replyToMessageId: value['replyToMessageId']?.toString(),
      replyToSenderId: value['replyToSenderId']?.toString(),
      replyToText: value['replyToText']?.toString(),
      edited: value['edited'] == true,
      editedAt: _parseOptionalDate(value['editedAt']),
      audio: value['audio'] == true,
      audioBase64: value['audioBase64']?.toString(),
      audioMimeType: value['audioMimeType']?.toString(),
      audioDurationSeconds: (value['audioDurationSeconds'] as num?)?.round(),
      image: value['image'] == true,
      imageBase64: value['imageBase64']?.toString(),
      imageMimeType: value['imageMimeType']?.toString(),
      reactions: (value['reactions'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) {
            final reaction = Map<String, dynamic>.from(item);
            return ChatMessageReaction(
              userId: (reaction['userId'] ?? '').toString(),
              emoji: (reaction['emoji'] ?? '').toString(),
              reactedAt: _parseOptionalDate(reaction['reactedAt']),
            );
          })
          .where((reaction) =>
              reaction.userId.isNotEmpty && reaction.emoji.isNotEmpty)
          .toList(),
    );
  }

  QuickShortcut _parseShortcut(Map<String, dynamic> value) {
    return QuickShortcut(
      id: value['id'].toString(),
      label: (value['label'] ?? 'Shortcut').toString(),
      type: _parseShortcutType(
          (value['actionType'] ?? value['type'] ?? 'call').toString()),
      value: (value['actionValue'] ?? value['value'] ?? '').toString(),
    );
  }

  Map<String, dynamic> _userToJson(AppUser user) {
    return {
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'phone': user.phone,
      'childMode': user.childMode,
      'relation': user.relation,
      'outsideHouse': user.outsideHouse,
      'birthDate': user.birthDate?.toIso8601String(),
      'lastLocation': user.lastLocation == null
          ? null
          : {'lat': user.lastLocation!.lat, 'lng': user.lastLocation!.lng},
      'locationStatusUpdatedAt':
          user.locationStatusUpdatedAt?.toIso8601String(),
      'notificationPreferences': {
        'needAlerts': user.notificationPreferences.needAlerts,
        'emergencyAlerts': user.notificationPreferences.emergencyAlerts,
        'chatMessages': user.notificationPreferences.chatMessages,
      },
    };
  }

  Map<String, dynamic> _houseToJson(House house) {
    return {
      'id': house.id,
      'name': house.name,
      'address': house.address,
      'createdBy': house.createdBy,
      'specialNumber': house.specialNumber,
      'location': house.location == null
          ? null
          : {'lat': house.location!.lat, 'lng': house.location!.lng},
    };
  }

  Map<String, dynamic> _cachedHouseStateToJson() {
    final activeHouse = house;
    return {
      if (activeHouse != null) 'house': _houseToJson(activeHouse),
      'houses': availableHouses.map(_houseToJson).toList(),
      'members': members.map(_userToJson).toList(),
      'alerts': alerts.map(_alertToJson).toList(),
      'reminders': reminders.map(_reminderToJson).toList(),
      'messages':
          messages.take(_cachedMessageLimit).map(_messageToJson).toList(),
      'shortcuts': shortcuts.map(_shortcutToJson).toList(),
    };
  }

  Map<String, dynamic> _alertToJson(NeedAlert alert) {
    return {
      'id': alert.id,
      'title': alert.title,
      'note': alert.note,
      'emergency': alert.emergency,
      'quantity': alert.quantity,
      'targetMemberIds': alert.targetMemberIds,
      'createdBy': alert.createdBy,
      'createdAt': alert.createdAt.toIso8601String(),
      'status': alert.status == AlertStatus.bought ? 'bought' : 'open',
      'bought': alert.boughtBy == null &&
              alert.boughtQuantity == null &&
              alert.boughtPrice == null &&
              alert.boughtAt == null
          ? null
          : {
              'by': alert.boughtBy,
              'quantity': alert.boughtQuantity,
              'price': alert.boughtPrice,
              'at': alert.boughtAt?.toIso8601String(),
            },
    };
  }

  Map<String, dynamic> _reminderToJson(FamilyReminder reminder) {
    return {
      'id': reminder.id,
      'title': reminder.title,
      'note': reminder.note,
      'dueAt': reminder.dueAt.toIso8601String(),
      'ringTimes': reminder.ringTimes,
      'recurrence': reminder.recurrence,
      'recurrenceWeekdays': reminder.recurrenceWeekdays,
      'createdBy': reminder.createdBy,
      'isBirthday': reminder.isBirthday,
      'birthdayMemberId': reminder.birthdayMemberId,
    };
  }

  Map<String, dynamic> _messageToJson(ChatMessage message) {
    return {
      'id': message.id,
      'senderId': message.senderId,
      'text': message.text,
      'createdAt': message.createdAt.toIso8601String(),
      'system': message.system,
      'receivedBy': message.receivedBy,
      'seenBy': message.seenBy,
      'replyToMessageId': message.replyToMessageId,
      'replyToSenderId': message.replyToSenderId,
      'replyToText': message.replyToText,
      'edited': message.edited,
      'editedAt': message.editedAt?.toIso8601String(),
      'audio': message.audio,
      'audioBase64': message.audioBase64,
      'audioMimeType': message.audioMimeType,
      'audioDurationSeconds': message.audioDurationSeconds,
      'image': message.image,
      'imageBase64': message.imageBase64,
      'imageMimeType': message.imageMimeType,
      'reactions': message.reactions
          .map((reaction) => {
                'userId': reaction.userId,
                'emoji': reaction.emoji,
                'reactedAt': reaction.reactedAt?.toIso8601String(),
              })
          .toList(),
    };
  }

  Map<String, dynamic> _shortcutToJson(QuickShortcut shortcut) {
    return {
      'id': shortcut.id,
      'label': shortcut.label,
      'actionType': shortcut.type.name,
      'actionValue': shortcut.value,
    };
  }

  ShortcutType _parseShortcutType(String value) {
    return ShortcutType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ShortcutType.call,
    );
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  DateTime? _parseOptionalDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _locationAddress(GeoPoint location) {
    return 'Lat ${location.lat.toStringAsFixed(6)}, Lng ${location.lng.toStringAsFixed(6)}';
  }

  double _distanceMeters(GeoPoint a, GeoPoint b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(b.lat - a.lat);
    final dLng = _degreesToRadians(b.lng - a.lng);
    final lat1 = _degreesToRadians(a.lat);
    final lat2 = _degreesToRadians(b.lat);
    final haversine = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;
}
