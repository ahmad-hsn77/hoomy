import 'package:flutter/material.dart';

import '../core/localization/app_localizations.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onTap;
  final String? info;
  final IconData infoIcon;

  const SectionHeader({
    super.key,
    required this.title,
    required this.action,
    required this.onTap,
    this.info,
    this.infoIcon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(infoIcon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (info != null) ...[
                  const SizedBox(width: 4),
                  _SectionInfoButton(
                    title: title,
                    info: info!,
                    icon: infoIcon,
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: color,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }
}

class _SectionInfoButton extends StatelessWidget {
  final String title;
  final String info;
  final IconData icon;

  const _SectionInfoButton({
    required this.title,
    required this.info,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.tr('aboutSection', {'title': title}),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => _FriendlyInfoDialog(
            title: title,
            info: info,
            icon: icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.info_outline,
            size: 11,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _FriendlyInfoDialog extends StatelessWidget {
  final String title;
  final String info;
  final IconData icon;
  final Color color;

  const _FriendlyInfoDialog({
    required this.title,
    required this.info,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Text(
        info,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.t('gotIt')),
        ),
      ],
    );
  }
}
