import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';
import '../services/startup_logger.dart';
import '../view_models/app_view_model.dart';
import 'auth/auth_screen.dart';
import 'house/house_selection_screen.dart';
import 'house/house_setup_screen.dart';
import 'shell_screen.dart';

class AppRoot extends StatefulWidget {
  final AppViewModel viewModel;

  const AppRoot({super.key, required this.viewModel});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _firstUsableScreenLogged = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        if (widget.viewModel.isRestoringSession) {
          return const _StartupLoadingScreen();
        }
        _logFirstUsableScreenAfterFrame();
        if (widget.viewModel.currentUser == null) {
          return AuthScreen(viewModel: widget.viewModel);
        }
        if (widget.viewModel.needsHouseSelection) {
          return HouseSelectionScreen(viewModel: widget.viewModel);
        }
        if (widget.viewModel.house == null) {
          return HouseSetupScreen(viewModel: widget.viewModel);
        }
        return ShellScreen(viewModel: widget.viewModel);
      },
    );
  }

  void _logFirstUsableScreenAfterFrame() {
    if (_firstUsableScreenLogged) return;
    _firstUsableScreenLogged = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      StartupLogger.mark('First screen rendered');
      widget.viewModel.initializeDeferredStartupTasks();
    });
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF7FFFC),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 118,
                  height: 118,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/illustrations/app_icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  context.l10n.t('hoomy'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F766E),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.t('gettingHomeReady'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      backgroundColor: const Color(0xFFDDF8F1),
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
