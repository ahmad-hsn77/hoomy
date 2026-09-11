import 'package:flutter/material.dart';

import '../../../core/constants/family_relations.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../models/need_alert.dart';
import '../../../view_models/app_view_model.dart';

class AlertEditor extends StatefulWidget {
  final AppViewModel viewModel;

  const AlertEditor({super.key, required this.viewModel});

  @override
  State<AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends State<AlertEditor> {
  final title = TextEditingController();
  final note = TextEditingController();
  final quantity = TextEditingController();
  bool emergency = false;
  String? localError;
  bool isSaving = false;
  final selectedMembers = <String>{};

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentUser = widget.viewModel.currentUser;
    final recipients = widget.viewModel.members.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t('addMissingItem'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
                controller: title,
                decoration: InputDecoration(labelText: l10n.t('itemOrNeed'))),
            const SizedBox(height: 8),
            TextField(
                controller: quantity,
                decoration:
                    InputDecoration(labelText: l10n.t('quantityOptional'))),
            const SizedBox(height: 8),
            TextField(
                controller: note,
                decoration: InputDecoration(labelText: l10n.t('noteOptional'))),
            const SizedBox(height: 8),
            SwitchListTile(
              value: emergency,
              onChanged: (value) => setState(() => emergency = value),
              title: Text(l10n.t('emergencyRing')),
              subtitle: Text(l10n.t('emergencyRingInfo')),
            ),
            const SizedBox(height: 8),
            Text(l10n.t('sendToSpecificMembers'),
                style: Theme.of(context).textTheme.titleMedium),
            if (recipients.isEmpty)
              ListTile(
                leading: const Icon(Icons.group_off_outlined),
                title: Text(l10n.t('noOtherMembersYet')),
                subtitle: Text(l10n.t('addMembersFirst')),
              )
            else
              ...recipients.map(
                (member) => CheckboxListTile(
                  value: selectedMembers.contains(member.id),
                  onChanged: (value) => setState(() {
                    value == true
                        ? selectedMembers.add(member.id)
                        : selectedMembers.remove(member.id);
                  }),
                  title: Text(member.name),
                  subtitle: Text(l10n.relation(relationshipLabelFor(
                    currentUserRelation: currentUser?.relation ?? 'Member',
                    memberRelation: member.relation,
                    isCurrentUser: member.id == currentUser?.id,
                  ))),
                ),
              ),
            if (localError != null) ...[
              const SizedBox(height: 8),
              Text(localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isSaving ? null : _save,
              icon: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(isSaving ? l10n.t('sending') : l10n.t('sendAlert')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final user = widget.viewModel.currentUser;
    if (user == null || title.text.trim().isEmpty) return;

    setState(() {
      localError = null;
      isSaving = true;
    });
    final targetMemberIds = selectedMembers.toList();

    final saved = await widget.viewModel.addAlert(
      NeedAlert(
        id: widget.viewModel.nextId('a'),
        title: title.text.trim(),
        note: note.text.trim(),
        quantity: quantity.text.trim(),
        emergency: emergency,
        targetMemberIds: targetMemberIds,
        createdBy: user.id,
        createdAt: DateTime.now(),
      ),
    );
    if (saved && mounted) {
      Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() {
        isSaving = false;
        localError = widget.viewModel.errorMessage ??
            context.l10n.t('couldNotSaveAlert');
      });
    }
  }
}
