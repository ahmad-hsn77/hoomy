import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/localization/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../services/hoomy_analytics_service.dart';
import '../view_models/app_view_model.dart';
import '../views/app_root.dart';

class HoomyApp extends StatefulWidget {
  const HoomyApp({super.key});

  @override
  State<HoomyApp> createState() => _HoomyAppState();
}

class _HoomyAppState extends State<HoomyApp> {
  late final AppViewModel viewModel = AppViewModel.seeded();

  @override
  void initState() {
    super.initState();
    HoomyAnalyticsService.instance.initialize();
    viewModel.restoreSession();
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) => MaterialApp(
        title: 'Hoomy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: Locale(viewModel.languageCode),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.15,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        navigatorObservers: [HoomyAnalyticsNavigatorObserver()],
        home: AppRoot(viewModel: viewModel),
      ),
    );
  }
}
