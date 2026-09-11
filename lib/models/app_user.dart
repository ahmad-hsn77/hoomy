import 'house.dart';

class NotificationPreferences {
  final bool needAlerts;
  final bool emergencyAlerts;
  final bool chatMessages;

  const NotificationPreferences({
    this.needAlerts = true,
    this.emergencyAlerts = true,
    this.chatMessages = true,
  });

  NotificationPreferences copyWith({
    bool? needAlerts,
    bool? emergencyAlerts,
    bool? chatMessages,
  }) {
    return NotificationPreferences(
      needAlerts: needAlerts ?? this.needAlerts,
      emergencyAlerts: emergencyAlerts ?? this.emergencyAlerts,
      chatMessages: chatMessages ?? this.chatMessages,
    );
  }
}

const Object _unchanged = Object();

class AppUser {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final bool childMode;
  final String relation;
  final bool outsideHouse;
  final DateTime? birthDate;
  final GeoPoint? lastLocation;
  final DateTime? locationStatusUpdatedAt;
  final NotificationPreferences notificationPreferences;

  const AppUser({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.childMode = false,
    this.relation = 'Member',
    this.outsideHouse = true,
    this.birthDate,
    this.lastLocation,
    this.locationStatusUpdatedAt,
    this.notificationPreferences = const NotificationPreferences(),
  });

  AppUser copyWith({
    String? name,
    Object? phone = _unchanged,
    String? relation,
    bool? outsideHouse,
    Object? birthDate = _unchanged,
    Object? lastLocation = _unchanged,
    Object? locationStatusUpdatedAt = _unchanged,
    NotificationPreferences? notificationPreferences,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email,
      phone: identical(phone, _unchanged) ? this.phone : phone as String?,
      childMode: childMode,
      relation: relation ?? this.relation,
      outsideHouse: outsideHouse ?? this.outsideHouse,
      birthDate: identical(birthDate, _unchanged)
          ? this.birthDate
          : birthDate as DateTime?,
      lastLocation: identical(lastLocation, _unchanged)
          ? this.lastLocation
          : lastLocation as GeoPoint?,
      locationStatusUpdatedAt: identical(locationStatusUpdatedAt, _unchanged)
          ? this.locationStatusUpdatedAt
          : locationStatusUpdatedAt as DateTime?,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
    );
  }
}
