import 'dart:async';

import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';
import '../services/alert_notification_service.dart';
import '../services/app_update_service.dart';
import '../services/hoomy_analytics_service.dart';
import '../services/push_notification_service.dart';
import '../view_models/app_view_model.dart';
import 'calendar/calendar_screen.dart';
import 'chat/chat_screen.dart';
import 'home/home_screen.dart';
import 'settings/settings_screen.dart';

class ShellScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const ShellScreen({super.key, required this.viewModel});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int index = 0;
  StreamSubscription<String>? _notificationTapSubscription;
  StreamSubscription<void>? _chatOpenSubscription;

  @override
  void initState() {
    super.initState();
    widget.viewModel.setChatVisible(index == 1);
    unawaited(HoomyAnalyticsService.instance
        .logScreenView(_screenNameForIndex(index)));
    _notificationTapSubscription = hoomyNotificationTaps.listen((payload) {
      if (_isChatPayload(payload)) _openChat();
    });
    _chatOpenSubscription = hoomyChatOpenRequests.listen((_) => _openChat());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payload =
          AlertNotificationService.instance.takeInitialNotificationPayload();
      if (_isChatPayload(payload)) {
        _openChat();
      }
      _checkForUpdatesOnHome();
    });
  }

  @override
  void dispose() {
    unawaited(_notificationTapSubscription?.cancel());
    unawaited(_chatOpenSubscription?.cancel());
    widget.viewModel.setChatVisible(false);
    super.dispose();
  }

  void _selectDestination(int value) {
    setState(() => index = value);
    if (value == 1) {
      widget.viewModel.setChatVisible(true);
    } else {
      widget.viewModel.setChatVisible(false);
    }
    if (value == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForUpdatesOnHome();
      });
    }
  }

  String _screenNameForIndex(int value) {
    return switch (value) {
      0 => 'home',
      1 => 'chat',
      2 => 'calendar',
      3 => 'settings',
      _ => 'unknown',
    };
  }

  bool _isChatPayload(String? payload) =>
      payload == 'chat' || payload == 'chat-summary';

  void _openChat() {
    if (!mounted) return;
    if (index == 1) {
      widget.viewModel.setChatVisible(true);
      return;
    }
    _selectDestination(1);
  }

  void _checkForUpdatesOnHome() {
    if (!mounted || index != 0) return;
    AppUpdateService.checkAndPrompt(
      context,
      viewModel: widget.viewModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (index == 1 && widget.viewModel.unreadChatMessageCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && index == 1) widget.viewModel.setChatVisible(true);
      });
    }

    final pages = [
      HomeScreen(viewModel: widget.viewModel),
      ChatScreen(viewModel: widget.viewModel),
      CalendarScreen(viewModel: widget.viewModel),
      SettingsScreen(viewModel: widget.viewModel),
    ];

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || index == 0) return;
        _selectDestination(0);
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: widget.viewModel,
          builder: (context, _) => pages[index],
        ),
        bottomNavigationBar: AnimatedBuilder(
          animation: widget.viewModel,
          builder: (context, _) {
            if (index == 1 && widget.viewModel.unreadChatMessageCount > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && index == 1) {
                  widget.viewModel.setChatVisible(true);
                }
              });
            }

            return DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavItem(
                        selected: index == 0,
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: l10n.t('home'),
                        onTap: () => _selectDestination(0),
                      ),
                      _NavItem(
                        selected: index == 1,
                        icon: Icons.chat_bubble_outline,
                        selectedIcon: Icons.chat_bubble_rounded,
                        label: l10n.t('chat'),
                        unreadCount: widget.viewModel.unreadChatMessageCount,
                        onTap: () => _selectDestination(1),
                      ),
                      _NavItem(
                        selected: index == 2,
                        icon: Icons.calendar_month_outlined,
                        selectedIcon: Icons.calendar_month_rounded,
                        label: l10n.t('calendar'),
                        onTap: () => _selectDestination(2),
                      ),
                      _NavItem(
                        selected: index == 3,
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings_rounded,
                        label: l10n.t('settings'),
                        onTap: () => _selectDestination(3),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int unreadCount;
  final VoidCallback onTap;

  const _NavItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF64748B);
    final item = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 52,
      height: 44,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFFDF8) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        selected ? selectedIcon : icon,
        color: color,
        size: 24,
        semanticLabel: label,
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: unreadCount > 0
          ? Badge(
              label: Text(unreadCount > 9 ? '9+' : unreadCount.toString()),
              child: item,
            )
          : item,
    );
  }
}
