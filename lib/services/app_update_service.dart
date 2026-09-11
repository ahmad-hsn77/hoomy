import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/localization/app_localizations.dart';
import '../models/app_update_info.dart';
import '../view_models/app_view_model.dart';

class AppUpdateService {
  AppUpdateService._();

  static bool _checking = false;
  static String? _promptedVersion;

  static Future<void> checkAndPrompt(
    BuildContext context, {
    required AppViewModel viewModel,
    bool silentIfNoUpdate = true,
  }) async {
    if (_checking) return;
    _checking = true;
    try {
      final info = await viewModel.checkForUpdate();
      if (!context.mounted) return;
      if (!info.hasUpdate && !info.requiresUpdate) {
        if (!silentIfNoUpdate) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.t('appUpToDate'))),
          );
        }
        return;
      }
      if (_promptedVersion == info.latestVersion && !info.requiresUpdate) {
        return;
      }
      _promptedVersion = info.latestVersion;

      final shouldOpen = await _showUpdateDialog(context, info);
      if (shouldOpen == true && context.mounted) {
        await openUpdateLink(context, info.updateUrl);
      }
    } catch (_) {
      if (!silentIfNoUpdate && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('couldNotCheckUpdates'))),
        );
      }
    } finally {
      _checking = false;
    }
  }

  static Future<void> downloadAndInstall(
    BuildContext context,
    String updateUrl,
  ) {
    return openUpdateLink(context, updateUrl);
  }

  static Future<void> openUpdateLink(
    BuildContext context,
    String updateUrl,
  ) async {
    final l10n = context.l10n;
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('invalidUpdateUrl'))),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('invalidUpdateUrl'))),
      );
    }
  }

  static Future<bool?> _showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          info.requiresUpdate
              ? Icons.system_security_update_warning_outlined
              : Icons.system_update_alt_outlined,
          color: Theme.of(dialogContext).colorScheme.primary,
        ),
        title: Text(
          info.requiresUpdate
              ? l10n.t('updateRequired')
              : l10n.t('updateAvailable'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('currentVersion', {
              'version': info.currentVersion,
            })),
            const SizedBox(height: 6),
            Text(l10n.tr('latestVersion', {
              'version': info.latestVersion,
            })),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.releaseNotes),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton.icon(
            onPressed: info.updateUrl.isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.open_in_browser_outlined),
            label: Text(l10n.t('downloadUpdate')),
          ),
        ],
      ),
    );
  }
}
