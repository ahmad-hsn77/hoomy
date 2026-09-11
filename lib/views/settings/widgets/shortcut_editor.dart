import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../models/quick_shortcut.dart';
import '../../../view_models/app_view_model.dart';

class ShortcutEditor extends StatefulWidget {
  final AppViewModel viewModel;
  final QuickShortcut? shortcut;

  const ShortcutEditor({
    super.key,
    required this.viewModel,
    this.shortcut,
  });

  @override
  State<ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<ShortcutEditor> {
  late final label = TextEditingController(text: widget.shortcut?.label ?? '');
  late final value = TextEditingController(text: widget.shortcut?.value ?? '');
  late ShortcutType type = widget.shortcut?.type ?? ShortcutType.call;
  String? localError;
  bool isSaving = false;

  @override
  void dispose() {
    label.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.shortcut == null
                ? l10n.t('addShortcut')
                : l10n.t('updateShortcut'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: label,
            decoration: InputDecoration(labelText: l10n.t('shortcutTitle')),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ShortcutType>(
            selected: {type},
            segments: [
              ButtonSegment(
                value: ShortcutType.call,
                icon: const Icon(Icons.call),
                label: Text(l10n.t('call')),
              ),
              ButtonSegment(
                value: ShortcutType.sms,
                icon: const Icon(Icons.sms_outlined),
                label: Text(l10n.t('sms')),
              ),
              ButtonSegment(
                value: ShortcutType.appMessage,
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(l10n.t('chat')),
              ),
            ],
            onSelectionChanged: (value) => setState(() => type = value.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: value,
            decoration: InputDecoration(
              labelText: type == ShortcutType.appMessage
                  ? l10n.t('messageToSendInFamilyChat')
                  : l10n.t('phoneNumber'),
            ),
            keyboardType: type == ShortcutType.appMessage
                ? TextInputType.text
                : TextInputType.phone,
          ),
          if (localError != null) ...[
            const SizedBox(height: 8),
            Text(
              localError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: isSaving ? null : _save,
            icon: isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.shortcut == null ? Icons.add : Icons.check),
            label: Text(isSaving
                ? l10n.t('saving')
                : widget.shortcut == null
                    ? l10n.t('addShortcut')
                    : l10n.t('updateShortcut')),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (label.text.trim().isEmpty || value.text.trim().isEmpty) {
      setState(() => localError = context.l10n.t('completeShortcutFields'));
      return;
    }

    setState(() {
      localError = null;
      isSaving = true;
    });
    final model = QuickShortcut(
      id: widget.shortcut?.id ?? widget.viewModel.nextId('s'),
      label: label.text.trim(),
      type: type,
      value: value.text.trim(),
    );
    final saved = widget.shortcut == null
        ? await widget.viewModel.addShortcut(model)
        : await widget.viewModel.updateShortcut(model);
    if (saved && mounted) {
      Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() {
        isSaving = false;
        localError = widget.viewModel.errorMessage ??
            context.l10n.t('couldNotSaveShortcut');
      });
    }
  }
}
