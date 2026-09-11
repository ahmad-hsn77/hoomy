import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/app_user.dart';
import '../../view_models/app_view_model.dart';

class ProfileScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const ProfileScreen({super.key, required this.viewModel});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final nameController = TextEditingController();
  late final phoneController = TextEditingController();
  DateTime? birthDate;
  bool editing = false;
  bool saving = false;
  String? localError;

  AppUser? get user => widget.viewModel.currentUser;

  @override
  void initState() {
    super.initState();
    _resetFields();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentUser = user;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoomyTopBar(
            title: l10n.t('profile'),
            leadingIcon: Icons.arrow_back_rounded,
            onLeadingTap: () => Navigator.pop(context),
            trailingIcon: editing ? Icons.close_rounded : Icons.edit_rounded,
            onTrailingTap: saving
                ? null
                : () => setState(() {
                      if (editing) _resetFields();
                      editing = !editing;
                      localError = null;
                    }),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileHeader(user: currentUser),
                  const SizedBox(height: 22),
                  if (editing)
                    _ProfileEditor(
                      nameController: nameController,
                      phoneController: phoneController,
                      birthDate: birthDate,
                      saving: saving,
                      localError: localError,
                      onPickBirthday: _pickBirthday,
                      onClearBirthday: () => setState(() => birthDate = null),
                      onSave: _saveProfile,
                    )
                  else ...[
                    _ProfileInfoCard(user: currentUser),
                    const SizedBox(height: 22),
                    HoomyButton2(
                      label: l10n.t('editProfile'),
                      icon: Icons.edit_rounded,
                      onPressed: () => setState(() => editing = true),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetFields() {
    final currentUser = user;
    nameController.text = currentUser?.name ?? '';
    phoneController.text = currentUser?.phone ?? '';
    birthDate = currentUser?.birthDate;
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => birthDate = picked);
    }
  }

  Future<void> _saveProfile() async {
    final l10n = context.l10n;
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    if (name.isEmpty) {
      setState(() => localError = l10n.t('nameRequired'));
      return;
    }

    setState(() {
      saving = true;
      localError = null;
    });
    final saved = await widget.viewModel.updateMyProfile(
      name: name,
      phone: phone.isEmpty ? null : phone,
      birthDate: birthDate,
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (saved) {
      setState(() => editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('profileSaved'))),
      );
      return;
    }
    setState(() {
      localError =
          widget.viewModel.errorMessage ?? l10n.t('couldNotSaveProfile');
    });
  }
}

class HoomyTopBar extends StatelessWidget {
  final String title;
  final IconData leadingIcon;
  final VoidCallback? onLeadingTap;
  final IconData trailingIcon;
  final VoidCallback? onTrailingTap;

  const HoomyTopBar({
    super.key,
    required this.title,
    required this.leadingIcon,
    required this.onLeadingTap,
    required this.trailingIcon,
    required this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                onPressed: onLeadingTap,
                icon: Icon(leadingIcon),
              ),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              IconButton(
                onPressed: onTrailingTap,
                icon: Icon(trailingIcon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HoomyButton2 extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  const HoomyButton2({
    super.key,
    required this.label,
    required this.icon,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AppUser? user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFEFFDF8),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            _initial(user?.name),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user?.name ?? l10n.t('member'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          user?.relation ?? l10n.t('member'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF64748B),
              ),
        ),
      ],
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final AppUser? user;

  const _ProfileInfoCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ProfileCard(
      children: [
        _ProfileInfoRow(
          icon: Icons.badge_rounded,
          color: Theme.of(context).colorScheme.primary,
          label: l10n.t('fullName'),
          value: user?.name ?? l10n.t('member'),
        ),
        _ProfileDivider(),
        _ProfileInfoRow(
          icon: Icons.phone_rounded,
          color: const Color(0xFF0EA5E9),
          label: l10n.t('phoneNumber'),
          value: user?.phone?.isNotEmpty == true
              ? user!.phone!
              : l10n.t('noPhoneAdded'),
        ),
        _ProfileDivider(),
        _ProfileInfoRow(
          icon: Icons.mail_rounded,
          color: const Color(0xFF10B981),
          label: l10n.t('emailAddress'),
          value: user?.email?.isNotEmpty == true
              ? user!.email!
              : l10n.t('noEmailAdded'),
        ),
        _ProfileDivider(),
        _ProfileInfoRow(
          icon: Icons.cake_rounded,
          color: const Color(0xFFF97316),
          label: l10n.t('birthday'),
          value: user?.birthDate == null
              ? l10n.t('noBirthdayAdded')
              : DateFormat('MMMM d, y', l10n.localeName)
                  .format(user!.birthDate!),
        ),
      ],
    );
  }
}

class _ProfileEditor extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final DateTime? birthDate;
  final bool saving;
  final String? localError;
  final VoidCallback onPickBirthday;
  final VoidCallback onClearBirthday;
  final VoidCallback onSave;

  const _ProfileEditor({
    required this.nameController,
    required this.phoneController,
    required this.birthDate,
    required this.saving,
    required this.localError,
    required this.onPickBirthday,
    required this.onClearBirthday,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _ProfileCard(
      children: [
        TextField(
          controller: nameController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.t('fullName'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l10n.t('phoneNumber'),
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: saving ? null : onPickBirthday,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.t('birthday'),
              prefixIcon: const Icon(Icons.cake_outlined),
              suffixIcon: birthDate == null
                  ? null
                  : IconButton(
                      onPressed: saving ? null : onClearBirthday,
                      icon: const Icon(Icons.close),
                    ),
            ),
            child: Text(
              birthDate == null
                  ? l10n.t('tapToChooseBirthday')
                  : DateFormat('MMMM d, y', l10n.localeName).format(birthDate!),
            ),
          ),
        ),
        if (localError != null) ...[
          const SizedBox(height: 12),
          Text(
            localError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        HoomyButton2(
          label: saving ? l10n.t('saving') : l10n.t('saveProfile'),
          icon: Icons.check_rounded,
          loading: saving,
          onPressed: onSave,
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final List<Widget> children;

  const _ProfileCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 28, color: Color(0xFFE2E8F0));
  }
}

String _initial(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'H';
  return trimmed.substring(0, 1).toUpperCase();
}
