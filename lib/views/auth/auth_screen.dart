import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/localization/app_localizations.dart';
import '../../view_models/app_view_model.dart';

class AuthScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const AuthScreen({super.key, required this.viewModel});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final nameController = TextEditingController();
  final contactController = TextEditingController();
  final passwordController = TextEditingController();
  bool usePhone = true;
  bool childMode = false;
  bool signInMode = true;
  bool passwordVisible = false;

  @override
  void dispose() {
    nameController.dispose();
    contactController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SvgPicture.asset('assets/illustrations/family_home.svg',
                      height: 210),
                  const SizedBox(height: 20),
                  Text(l10n.t('hoomy'),
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('authSubtitle'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  if (!childMode)
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: true,
                            label: Text(l10n.t('phone')),
                            icon: const Icon(Icons.phone_outlined)),
                        ButtonSegment(
                            value: false,
                            label: Text(l10n.t('email')),
                            icon: const Icon(Icons.mail_outline)),
                      ],
                      selected: {usePhone},
                      onSelectionChanged: (value) =>
                          setState(() => usePhone = value.first),
                    ),
                  if (!childMode) const SizedBox(height: 12),
                  if (!signInMode || childMode) ...[
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: childMode && signInMode
                            ? l10n.t('childAccountName')
                            : l10n.t('yourName'),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!childMode)
                    TextField(
                      controller: contactController,
                      keyboardType: usePhone
                          ? TextInputType.phone
                          : TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: usePhone
                            ? l10n.t('phoneNumber')
                            : l10n.t('emailAddress'),
                        prefixIcon: Icon(usePhone
                            ? Icons.phone_outlined
                            : Icons.mail_outline),
                      ),
                    ),
                  if (!childMode) ...[
                    const SizedBox(height: 12),
                    _PasswordField(
                      controller: passwordController,
                      visible: passwordVisible,
                      onToggle: () =>
                          setState(() => passwordVisible = !passwordVisible),
                      label: l10n.t('password'),
                    ),
                    if (signInMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: widget.viewModel.isBusy
                              ? null
                              : _showForgotPasswordSheet,
                          child: Text(l10n.t('forgotPassword')),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: childMode,
                    onChanged: widget.viewModel.isBusy
                        ? null
                        : (value) => setState(() {
                              childMode = value;
                              if (childMode) {
                                usePhone = true;
                                passwordController.clear();
                              }
                            }),
                    title: Text(signInMode
                        ? l10n.t('signInAsChild')
                        : l10n.t('stillYoungChild')),
                    subtitle: Text(signInMode
                        ? l10n.t('useUniqueChildName')
                        : l10n.t('noPhoneEmailChild')),
                  ),
                  if (widget.viewModel.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(widget.viewModel.errorMessage!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: widget.viewModel.isBusy ? null : _continue,
                    icon: widget.viewModel.isBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_forward),
                    label: Text(widget.viewModel.isBusy
                        ? l10n.t('connecting')
                        : signInMode
                            ? l10n.t('signIn')
                            : l10n.t('continue')),
                  ),
                  TextButton(
                    onPressed: widget.viewModel.isBusy
                        ? null
                        : () => setState(() {
                              signInMode = !signInMode;
                              childMode = false;
                              passwordController.clear();
                            }),
                    child: Text(signInMode
                        ? l10n.t('createNewAccount')
                        : l10n.t('alreadyHaveAccount')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _continue() async {
    final name = nameController.text.trim();
    final contact = contactController.text.trim();
    final password = passwordController.text.trim();
    if ((!signInMode && name.isEmpty) ||
        (childMode && name.isEmpty) ||
        (!childMode && (contact.isEmpty || password.isEmpty))) {
      return;
    }

    if (signInMode) {
      await widget.viewModel.loginUser(
        phone: !childMode && usePhone ? contact : null,
        email: !childMode && !usePhone ? contact : null,
        childName: childMode ? name : null,
        password: childMode ? null : password,
      );
    } else {
      await widget.viewModel.registerUser(
        name: name,
        phone: !childMode && usePhone ? contact : null,
        email: !childMode && !usePhone ? contact : null,
        password: childMode ? null : password,
        childMode: childMode,
      );
    }
  }

  void _showForgotPasswordSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ForgotPasswordSheet(
        viewModel: widget.viewModel,
        usePhone: usePhone,
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggle;
  final String label;

  const _PasswordField({
    required this.controller,
    required this.visible,
    required this.onToggle,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
        ),
      ),
    );
  }
}

class _ForgotPasswordSheet extends StatefulWidget {
  final AppViewModel viewModel;
  final bool usePhone;

  const _ForgotPasswordSheet({required this.viewModel, required this.usePhone});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final contactController = TextEditingController();
  final passwordController = TextEditingController();
  bool usePhone = true;
  bool requested = false;
  bool passwordVisible = false;

  @override
  void initState() {
    super.initState();
    usePhone = widget.usePhone;
  }

  @override
  void dispose() {
    contactController.dispose();
    passwordController.dispose();
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
          Text(l10n.t('resetPassword'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: true,
                  label: Text(l10n.t('phone')),
                  icon: const Icon(Icons.phone_outlined)),
              ButtonSegment(
                  value: false,
                  label: Text(l10n.t('email')),
                  icon: const Icon(Icons.mail_outline)),
            ],
            selected: {usePhone},
            onSelectionChanged: (value) =>
                setState(() => usePhone = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contactController,
            keyboardType:
                usePhone ? TextInputType.phone : TextInputType.emailAddress,
            decoration: InputDecoration(
                labelText:
                    usePhone ? l10n.t('phoneNumber') : l10n.t('emailAddress')),
          ),
          const SizedBox(height: 12),
          _PasswordField(
            controller: passwordController,
            visible: passwordVisible,
            onToggle: () => setState(() => passwordVisible = !passwordVisible),
            label: l10n.t('password'),
          ),
          if (widget.viewModel.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(widget.viewModel.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (requested) ...[
            const SizedBox(height: 8),
            Text(l10n.t('resetRequestSent')),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.viewModel.isBusy ? null : _reset,
            icon: widget.viewModel.isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_reset),
            label: Text(widget.viewModel.isBusy
                ? l10n.t('resetting')
                : l10n.t('resetPassword')),
          ),
        ],
      ),
    );
  }

  Future<void> _reset() async {
    final contact = contactController.text.trim();
    final newPassword = passwordController.text.trim();
    if (contact.isEmpty || newPassword.isEmpty) return;

    final requestedOk = await widget.viewModel.requestPasswordReset(
      phone: usePhone ? contact : null,
      email: usePhone ? null : contact,
    );
    if (mounted) setState(() => requested = requestedOk);
    if (!requestedOk) return;

    final reset = await widget.viewModel.resetPassword(
      phone: usePhone ? contact : null,
      email: usePhone ? null : contact,
      newPassword: newPassword,
    );
    if (reset && mounted) Navigator.pop(context);
  }
}
