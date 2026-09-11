import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';

class HoomyAnalyticsService {
  HoomyAnalyticsService._();

  static final HoomyAnalyticsService instance = HoomyAnalyticsService._();

  FirebaseAnalytics? _analytics;
  Future<void>? _initialization;

  Future<void> initialize() {
    if (kIsWeb) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _analytics = FirebaseAnalytics.instance;
      await _analytics?.setAnalyticsCollectionEnabled(true);
      debugPrint('[HoomyAnalytics] initialized');
    } catch (error) {
      debugPrint('[HoomyAnalytics] init failed: $error');
    }
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (kIsWeb) return;
    try {
      await initialize();
      await _analytics?.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (error) {
      debugPrint('[HoomyAnalytics] event $name failed: $error');
    }
  }

  Future<void> logScreenView(String screenName) async {
    if (kIsWeb) return;
    try {
      await initialize();
      await _analytics?.logScreenView(screenName: screenName);
    } catch (error) {
      debugPrint('[HoomyAnalytics] screen $screenName failed: $error');
    }
  }

  Future<void> setSignedInUser(String? userId) async {
    if (kIsWeb) return;
    try {
      await initialize();
      await _analytics?.setUserId(id: userId);
    } catch (error) {
      debugPrint('[HoomyAnalytics] set user failed: $error');
    }
  }
}

class HoomyAnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _logRoute(newRoute);
  }

  void _logRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    HoomyAnalyticsService.instance.logScreenView(name);
  }
}
