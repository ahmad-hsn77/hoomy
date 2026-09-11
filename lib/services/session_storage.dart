import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  static const _tokenKey = 'hoomy.auth.token';
  static const _userKey = 'hoomy.auth.user';
  static const _houseKey = 'hoomy.house';
  static const _houseStateKey = 'hoomy.house.state';
  static const _continuousLocationKey = 'hoomy.location.continuous';
  static const _languageKey = 'hoomy.language';

  Future<void> saveSession({
    required String token,
    required String userJson,
    String? houseJson,
    String? houseStateJson,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, userJson);
    if (houseJson == null) {
      await prefs.remove(_houseKey);
    } else {
      await prefs.setString(_houseKey, houseJson);
    }
    if (houseStateJson == null) {
      await prefs.remove(_houseStateKey);
    } else {
      await prefs.setString(_houseStateKey, houseStateJson);
    }
  }

  Future<void> saveHouse(String houseJson, {String? houseStateJson}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_houseKey, houseJson);
    if (houseStateJson != null) {
      await prefs.setString(_houseStateKey, houseStateJson);
    }
  }

  Future<void> saveContinuousLocationUpdates(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_continuousLocationKey, enabled);
  }

  Future<bool> readContinuousLocationUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_continuousLocationKey) ?? false;
  }

  Future<void> saveLanguageCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  Future<String> readLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'en';
  }

  Future<BootstrapSession> readBootstrapSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    return BootstrapSession(
      languageCode: prefs.getString(_languageKey) ?? 'en',
      continuousLocationUpdates: prefs.getBool(_continuousLocationKey) ?? false,
      session: token == null || userJson == null
          ? null
          : SavedSession(
              token: token,
              userJson: userJson,
              houseJson: prefs.getString(_houseKey),
              houseStateJson: prefs.getString(_houseStateKey),
            ),
    );
  }

  Future<SavedSession?> readSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (token == null || userJson == null) return null;
    return SavedSession(
      token: token,
      userJson: userJson,
      houseJson: prefs.getString(_houseKey),
      houseStateJson: prefs.getString(_houseStateKey),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_houseKey);
    await prefs.remove(_houseStateKey);
    await prefs.remove(_continuousLocationKey);
  }
}

class BootstrapSession {
  final String languageCode;
  final bool continuousLocationUpdates;
  final SavedSession? session;

  const BootstrapSession({
    required this.languageCode,
    required this.continuousLocationUpdates,
    required this.session,
  });
}

class SavedSession {
  final String token;
  final String userJson;
  final String? houseJson;
  final String? houseStateJson;

  const SavedSession({
    required this.token,
    required this.userJson,
    this.houseJson,
    this.houseStateJson,
  });
}
