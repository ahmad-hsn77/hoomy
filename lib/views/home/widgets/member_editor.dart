import 'package:flutter/material.dart';

import '../../../core/constants/family_relations.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../view_models/app_view_model.dart';

class MemberEditor extends StatefulWidget {
  final AppViewModel viewModel;

  const MemberEditor({super.key, required this.viewModel});

  @override
  State<MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<MemberEditor> {
  final name = TextEditingController();
  final contact = TextEditingController();
  String relation = 'Mother';
  bool childMode = false;
  String? localError;
  bool isSaving = false;

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.t('addFamilyMember'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            selected: {childMode},
            segments: [
              ButtonSegment(
                value: false,
                label: Text(l10n.t('phone')),
                icon: const Icon(Icons.phone_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text(l10n.t('childName')),
                icon: const Icon(Icons.child_care),
              ),
            ],
            onSelectionChanged: (value) => setState(() {
              childMode = value.first;
              localError = null;
              name.clear();
              contact.clear();
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: childMode ? name : contact,
            keyboardType: childMode ? TextInputType.name : TextInputType.phone,
            decoration: InputDecoration(
              labelText: childMode
                  ? l10n.t('childAccountName')
                  : l10n.t('phoneNumber'),
              prefixIcon:
                  Icon(childMode ? Icons.person_outline : Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: relation,
            decoration: InputDecoration(labelText: l10n.t('familyRelation')),
            items: familyRelations
                .map((item) => DropdownMenuItem(
                    value: item, child: Text(l10n.relation(item))))
                .toList(),
            onChanged: (value) => setState(() => relation = value ?? relation),
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
                : const Icon(Icons.person_add_alt_1_outlined),
            label: Text(isSaving ? l10n.t('adding') : l10n.t('addMember')),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final childName = name.text.trim();
    final phone = contact.text.trim();
    if (childMode && childName.isEmpty) {
      setState(() => localError = context.l10n.t('enterChildAccountName'));
      return;
    }
    if (!childMode && phone.isEmpty) {
      setState(() => localError = context.l10n.t('enterPhoneNumber'));
      return;
    }
    setState(() {
      localError = null;
      isSaving = true;
    });
    final saved = await widget.viewModel.addMember(
      AppUser(
        id: widget.viewModel.nextId('u'),
        name: childMode ? childName : phone,
        phone: childMode ? null : phone,
        relation: relation,
        childMode: childMode,
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
            context.l10n.t('couldNotAddMember');
      });
    }
  }
}
