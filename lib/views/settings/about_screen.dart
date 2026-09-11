import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/app_update_info.dart';
import '../../services/app_update_service.dart';
import '../../view_models/app_view_model.dart';

class AboutScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const AboutScreen({super.key, required this.viewModel});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  AppUpdateInfo? updateInfo;
  String? errorMessage;
  bool checking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final info = updateInfo;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('aboutHoomy')),
        backgroundColor: const Color(0xFFF7FFFC),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFEFFDF8), Color(0xFFE0F2FE)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.home_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.t('hoomy'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('aboutHoomyBody'),
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InfoTile(
            icon: Icons.inventory_2_outlined,
            title: l10n.t('aboutNeedsTitle'),
            body: l10n.t('aboutNeedsBody'),
          ),
          _InfoTile(
            icon: Icons.notifications_active_outlined,
            title: l10n.t('aboutAlertsTitle'),
            body: l10n.t('aboutAlertsBody'),
          ),
          _InfoTile(
            icon: Icons.chat_bubble_outline,
            title: l10n.t('aboutChatTitle'),
            body: l10n.t('aboutChatBody'),
          ),
          _InfoTile(
            icon: Icons.calendar_month_outlined,
            title: l10n.t('aboutCalendarTitle'),
            body: l10n.t('aboutCalendarBody'),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.t('appVersion'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.tr('currentVersion', {
                    'version': AppConfig.appVersion,
                  })),
                  if (info != null) ...[
                    const SizedBox(height: 4),
                    Text(l10n.tr('latestVersion', {
                      'version': info.latestVersion,
                    })),
                    if (info.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(info.releaseNotes),
                    ],
                    const SizedBox(height: 10),
                    _UpdateStatusBanner(info: info),
                  ],
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: checking ? null : _checkForUpdate,
                    icon: checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt_outlined),
                    label: Text(checking
                        ? l10n.t('checkingUpdates')
                        : l10n.t('checkUpdates')),
                  ),
                  if (info?.hasUpdate == true && info!.updateUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: () => AppUpdateService.downloadAndInstall(
                          context,
                          info.updateUrl,
                        ),
                        icon: const Icon(Icons.open_in_browser_outlined),
                        label: Text(l10n.t('downloadUpdate')),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    final l10n = context.l10n;
    setState(() {
      checking = true;
      errorMessage = null;
    });
    try {
      final info = await widget.viewModel.checkForUpdate();
      if (!mounted) return;
      setState(() => updateInfo = info);
    } catch (_) {
      if (!mounted) return;
      setState(() => errorMessage = l10n.t('couldNotCheckUpdates'));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFEFF6FF),
            child: Icon(icon, color: const Color(0xFF2563EB)),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(body),
        ),
      ),
    );
  }
}

class _UpdateStatusBanner extends StatelessWidget {
  final AppUpdateInfo info;

  const _UpdateStatusBanner({required this.info});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = info.requiresUpdate
        ? const Color(0xFFDC2626)
        : info.hasUpdate
            ? const Color(0xFFB45309)
            : const Color(0xFF047857);
    final text = info.requiresUpdate
        ? l10n.t('updateRequired')
        : info.hasUpdate
            ? l10n.t('updateAvailable')
            : l10n.t('appUpToDate');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              info.hasUpdate
                  ? Icons.system_update_alt_outlined
                  : Icons.verified_outlined,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
