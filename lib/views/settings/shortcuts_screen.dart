import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/quick_shortcut.dart';
import '../../view_models/app_view_model.dart';
import 'widgets/shortcut_editor.dart';

class ShortcutsScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const ShortcutsScreen({super.key, required this.viewModel});

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  String? deletingShortcutId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('shortcutsTitle')),
        backgroundColor: const Color(0xFFF7FFFC),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShortcutSheet(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('add')),
      ),
      body: AnimatedBuilder(
        animation: widget.viewModel,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
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
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          l10n.t('shortcutsInfo'),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.35,
                                    color: const Color(0xFF475569),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.viewModel.shortcuts.isEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.touch_app_outlined,
                              color: Color(0xFFF97316)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.t('noShortcutsYet'),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...widget.viewModel.shortcuts.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _shortcutColor(item.type)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _shortcutIcon(item.type),
                                color: _shortcutColor(item.type),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _shortcutSubtitle(context, item),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF64748B),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.t('updateShortcut'),
                              onPressed: () =>
                                  _showShortcutSheet(context, shortcut: item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: l10n.t('deleteShortcut'),
                              onPressed: deletingShortcutId == null
                                  ? () => _deleteShortcut(context, item)
                                  : null,
                              icon: deletingShortcutId == item.id
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Color _shortcutColor(ShortcutType type) {
    return switch (type) {
      ShortcutType.call => const Color(0xFF10B981),
      ShortcutType.sms => const Color(0xFFF97316),
      ShortcutType.appMessage => const Color(0xFF0EA5E9),
    };
  }

  void _showShortcutSheet(BuildContext context, {QuickShortcut? shortcut}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ShortcutEditor(viewModel: widget.viewModel, shortcut: shortcut),
    );
  }

  Future<void> _deleteShortcut(
      BuildContext context, QuickShortcut shortcut) async {
    final confirmed = await _confirmDeleteShortcut(context, shortcut);
    if (!confirmed || !mounted) return;

    setState(() => deletingShortcutId = shortcut.id);
    final deleted = await widget.viewModel.deleteShortcut(shortcut);
    if (!mounted) return;

    setState(() => deletingShortcutId = null);
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.viewModel.errorMessage ??
                context.l10n.t('couldNotDeleteShortcut'))),
      );
    }
  }

  Future<bool> _confirmDeleteShortcut(
      BuildContext context, QuickShortcut shortcut) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('deleteShortcutQuestion')),
        content: Text(
            context.l10n.tr('deleteShortcutBody', {'label': shortcut.label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  IconData _shortcutIcon(ShortcutType type) {
    return switch (type) {
      ShortcutType.call => Icons.call,
      ShortcutType.sms => Icons.sms_outlined,
      ShortcutType.appMessage => Icons.chat_bubble_outline,
    };
  }

  String _shortcutSubtitle(BuildContext context, QuickShortcut shortcut) {
    return switch (shortcut.type) {
      ShortcutType.appMessage =>
        context.l10n.tr('familyChatValue', {'value': shortcut.value}),
      ShortcutType.sms => shortcut.value,
      ShortcutType.call => shortcut.value,
    };
  }
}
