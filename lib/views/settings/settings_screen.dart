import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/constants/family_relations.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/quick_shortcut.dart';
import '../../services/location_service.dart';
import '../../view_models/app_view_model.dart';
import '../house/house_qr_tools.dart';
import '../house/house_selection_screen.dart';
import '../profile/profile_screen.dart';
import 'about_screen.dart';
import 'shortcuts_screen.dart';
import 'widgets/shortcut_editor.dart';

class SettingsScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const SettingsScreen({super.key, required this.viewModel});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _houseIcon = 'assets/illustrations/settings_house.svg';
  static const _locationIcon = 'assets/illustrations/settings_location.svg';
  static const _shortcutsIcon = 'assets/illustrations/settings_shortcuts.svg';
  static const _aboutIcon = 'assets/illustrations/settings_about.svg';
  static const _accountIcon = 'assets/illustrations/settings_account.svg';
  static const _statusIcon = 'assets/illustrations/settings_status.svg';
  static const _copyIcon = 'assets/illustrations/settings_copy.svg';

  final locationService = LocationService();
  bool locating = false;
  String? locationStatusMessage;
  String? deletingShortcutId;
  bool updatingBirthday = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = widget.viewModel.currentUser;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 110),
        children: [
          _SettingsTitleBar(
            title: l10n.t('settings'),
            initial: (user?.name ?? l10n.t('member')).trim().isEmpty
                ? 'H'
                : (user?.name ?? l10n.t('member')).trim()[0].toUpperCase(),
            onProfileTap: _openProfile,
          ),
          const SizedBox(height: 18),
          _SettingsHeader(
            name: user?.name ?? l10n.t('member'),
            houseName: widget.viewModel.house?.name ?? l10n.t('hoomy'),
            outsideHouse: user?.outsideHouse ?? true,
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: l10n.t('language'),
            iconAsset: _aboutIcon,
            iconColor: const Color(0xFF7C3AED),
            color: const Color(0xFFF5F3FF),
            info: l10n.t('languageInfo'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: SegmentedButton<String>(
                  selected: {widget.viewModel.languageCode},
                  segments: [
                    ButtonSegment(
                      value: 'en',
                      label: Text(l10n.t('english')),
                    ),
                    ButtonSegment(
                      value: 'ar',
                      label: Text(l10n.t('arabic')),
                    ),
                  ],
                  onSelectionChanged: (value) =>
                      widget.viewModel.setLanguageCode(value.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('house'),
            iconAsset: _houseIcon,
            iconColor: const Color(0xFF0F766E),
            color: const Color(0xFFEFFDF8),
            info: l10n.t('houseInfo'),
            children: [
              ListTile(
                leading: const _SettingsSvgIcon(
                  assetName: _houseIcon,
                  color: Color(0xFF0F766E),
                ),
                title: Text(widget.viewModel.house?.name ?? l10n.t('house')),
                subtitle: Text(
                    widget.viewModel.house?.address.isNotEmpty == true
                        ? widget.viewModel.house!.address
                        : l10n.t('noAddressAdded')),
              ),
              if (widget.viewModel.house?.specialNumber?.isNotEmpty == true)
                ListTile(
                  leading: const _SettingsSvgIcon(
                    assetName: _copyIcon,
                    color: Color(0xFF0F766E),
                  ),
                  title: Text(l10n.t('houseSpecialNumber')),
                  subtitle: GestureDetector(
                    onLongPress: () => _copyHouseSpecialNumber(
                      widget.viewModel.house!.specialNumber!,
                    ),
                    child: Text(widget.viewModel.house!.specialNumber!),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: l10n.t('showQrCode'),
                        onPressed: () => showHouseQrDialog(
                          context,
                          widget.viewModel.house!.specialNumber!,
                        ),
                        icon: const Icon(Icons.qr_code_2_outlined),
                      ),
                      IconButton(
                        tooltip: l10n.t('copySpecialNumber'),
                        onPressed: () => _copyHouseSpecialNumber(
                          widget.viewModel.house!.specialNumber!,
                        ),
                        icon: const _SettingsSvgIcon(
                          assetName: _copyIcon,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(
                  Icons.swap_horiz_outlined,
                  color: Color(0xFF0F766E),
                ),
                title: Text(l10n.t('changeHouse')),
                subtitle: Text(l10n.t('changeHouseSubtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.viewModel.isBusy ? null : _showChangeHouseDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('location'),
            iconAsset: _locationIcon,
            iconColor: const Color(0xFFC2410C),
            color: const Color(0xFFFFF7ED),
            info: l10n.t('locationInfo'),
            children: [
              ListTile(
                leading: locating
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const _SettingsSvgIcon(
                        assetName: _locationIcon,
                        color: Color(0xFFC2410C),
                      ),
                title: Text(l10n.t('houseLocation')),
                subtitle: Text(widget.viewModel.house?.location == null
                    ? l10n.t('noHouseLocationSaved')
                    : l10n.t('houseLocationSaved')),
                trailing: const Icon(Icons.edit_location_alt_outlined),
                onTap: locating ? null : _confirmUpdateHouseLocation,
              ),
              ListTile(
                leading: locating
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const _SettingsSvgIcon(
                        assetName: _statusIcon,
                        color: Color(0xFFC2410C),
                      ),
                title: Text(l10n.t('myStatus')),
                subtitle: Text(locationStatusMessage ??
                    (user == null
                        ? l10n.t('signInToUpdateStatus')
                        : user.outsideHouse
                            ? l10n.t('outside')
                            : l10n.t('inside'))),
                trailing: TextButton(
                  onPressed: locating ? null : _refreshLocationStatus,
                  child: Text(l10n.t('update')),
                ),
              ),
              SwitchListTile(
                value: widget.viewModel.continuousLocationUpdates,
                onChanged: widget.viewModel.house?.location == null
                    ? null
                    : _toggleContinuousLocationUpdates,
                title: Text(l10n.t('autoUpdateStatus')),
                subtitle: Text(widget.viewModel.house?.location == null
                    ? l10n.t('saveHouseLocationFirst')
                    : l10n.t('refreshStatusEveryFew')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('notifications'),
            iconAsset: _statusIcon,
            iconColor: const Color(0xFF2563EB),
            color: const Color(0xFFEFF6FF),
            info: l10n.t('notificationsInfo'),
            children: [
              SwitchListTile(
                value: user?.notificationPreferences.needAlerts ?? true,
                onChanged: user == null || widget.viewModel.isBusy
                    ? null
                    : (value) => _updateNotificationPreferences(
                          user.notificationPreferences.copyWith(
                            needAlerts: value,
                          ),
                        ),
                secondary: const _SettingsSvgIcon(
                  assetName: _statusIcon,
                  color: Color(0xFF2563EB),
                ),
                title: Text(l10n.t('needAlertsSetting')),
                subtitle: Text(l10n.t('showMissingItemAlerts')),
              ),
              SwitchListTile(
                value: user?.notificationPreferences.emergencyAlerts ?? true,
                onChanged: user == null || widget.viewModel.isBusy
                    ? null
                    : (value) => _updateNotificationPreferences(
                          user.notificationPreferences.copyWith(
                            emergencyAlerts: value,
                          ),
                        ),
                secondary: const _SettingsSvgIcon(
                  assetName: _statusIcon,
                  color: Color(0xFF2563EB),
                ),
                title: Text(l10n.t('emergencyAlerts')),
                subtitle: Text(l10n.t('useLongerEmergencySound')),
              ),
              SwitchListTile(
                value: user?.notificationPreferences.chatMessages ?? true,
                onChanged: user == null || widget.viewModel.isBusy
                    ? null
                    : (value) => _updateNotificationPreferences(
                          user.notificationPreferences.copyWith(
                            chatMessages: value,
                          ),
                        ),
                secondary: const _SettingsSvgIcon(
                  assetName: _shortcutsIcon,
                  color: Color(0xFF2563EB),
                ),
                title: Text(l10n.t('familyChatMessages')),
                subtitle: Text(l10n.t('notifyChatNew')),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined,
                    color: Color(0xFF2563EB)),
                title: Text(l10n.t('pushStatus')),
                subtitle: Text(widget.viewModel.pushStatusMessage),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('shortcuts'),
            iconAsset: _shortcutsIcon,
            iconColor: const Color(0xFF4F46E5),
            color: const Color(0xFFEEF2FF),
            info: l10n.t('shortcutsInfo'),
            trailing: TextButton(
              onPressed: _openShortcuts,
              child: Text(l10n.t('viewAll')),
            ),
            children: [
              if (widget.viewModel.shortcuts.isEmpty)
                ListTile(
                  leading: const _SettingsSvgIcon(
                    assetName: _shortcutsIcon,
                    color: Color(0xFF4F46E5),
                  ),
                  title: Text(l10n.t('noShortcutsYet')),
                )
              else
                ...widget.viewModel.shortcuts.take(1).map(
                  (item) {
                    return ListTile(
                      leading: const _SettingsSvgIcon(
                        assetName: _shortcutsIcon,
                        color: Color(0xFF4F46E5),
                      ),
                      title: Text(item.label),
                      subtitle: Text(_shortcutSubtitle(item)),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: l10n.t('updateShortcut'),
                            onPressed: () => _showShortcutSheet(shortcut: item),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: l10n.t('deleteShortcut'),
                            onPressed: deletingShortcutId == null
                                ? () => _deleteShortcut(item)
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
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('about'),
            iconAsset: _aboutIcon,
            iconColor: const Color(0xFF475569),
            color: const Color(0xFFF8FAFC),
            info: l10n.t('aboutInfo'),
            children: [
              ListTile(
                leading: const _SettingsSvgIcon(
                  assetName: _aboutIcon,
                  color: Color(0xFF475569),
                ),
                title: Text(l10n.t('aboutHoomy')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openAbout,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsSection(
            title: l10n.t('account'),
            iconAsset: _accountIcon,
            iconColor: const Color(0xFFDC2626),
            color: const Color(0xFFFEF2F2),
            info: l10n.t('accountInfo'),
            children: [
              ListTile(
                leading: const _SettingsSvgIcon(
                  assetName: _accountIcon,
                  color: Color(0xFFDC2626),
                ),
                title: Text(l10n.t('profile')),
                subtitle: Text(user?.name ?? l10n.t('member')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openProfile,
              ),
              ListTile(
                leading: updatingBirthday
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cake_outlined, color: Color(0xFFDC2626)),
                title: Text(l10n.t('yourBirthday')),
                subtitle: Text(user?.birthDate == null
                    ? l10n.t('noBirthdayAdded')
                    : DateFormat('MMMM d, y').format(user!.birthDate!)),
                trailing: user?.birthDate == null
                    ? null
                    : IconButton(
                        tooltip: l10n.t('removeBirthday'),
                        onPressed: updatingBirthday ? null : _clearBirthday,
                        icon: const Icon(Icons.close),
                      ),
                onTap: updatingBirthday ? null : _pickBirthday,
              ),
              ListTile(
                leading: const _SettingsSvgIcon(
                  assetName: _accountIcon,
                  color: Color(0xFFDC2626),
                ),
                title: Text(l10n.t('signOut')),
                onTap: widget.viewModel.isBusy
                    ? null
                    : () async {
                        await widget.viewModel.signOut();
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _refreshLocationStatus() async {
    final l10n = context.l10n;
    if (widget.viewModel.house?.location == null) {
      setState(() => locationStatusMessage = l10n.t('saveHouseLocationFirst'));
      return;
    }

    final enabled = await locationService.isLocationServiceEnabled();
    if (!enabled && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('enableLocation')),
          content: Text(l10n.t('enableStatusLocationBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.t('ok')))
          ],
        ),
      );
      return;
    }

    setState(() {
      locating = true;
      locationStatusMessage = l10n.t('gettingCurrentLocation');
    });
    final location = await locationService.requestCurrentLocation();
    if (!mounted) return;

    if (location == null) {
      setState(() {
        locating = false;
        locationStatusMessage = l10n.t('couldNotGetLocation');
      });
      return;
    }

    final updated =
        await widget.viewModel.updateCurrentLocationStatus(location);
    if (!mounted) return;
    setState(() {
      locating = false;
      locationStatusMessage = updated
          ? (widget.viewModel.currentUser?.outsideHouse == true
              ? l10n.t('updatedOutside')
              : l10n.t('updatedInside'))
          : widget.viewModel.errorMessage ??
              l10n.t('couldNotUpdateLocationStatus');
    });
  }

  Future<void> _confirmUpdateHouseLocation() async {
    final l10n = context.l10n;
    if (widget.viewModel.house == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('updateHouseLocation')),
        content: Text(l10n.t('updateHouseLocationBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('update')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _updateHouseLocationFromDevice();
  }

  Future<void> _updateHouseLocationFromDevice() async {
    final l10n = context.l10n;
    final enabled = await locationService.isLocationServiceEnabled();
    if (!enabled && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('enableLocation')),
          content: Text(l10n.t('enableHouseLocationBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.t('ok')),
            )
          ],
        ),
      );
      return;
    }

    setState(() {
      locating = true;
      locationStatusMessage = l10n.t('gettingCurrentLocation');
    });
    final location = await locationService.requestCurrentLocation();
    if (!mounted) return;

    if (location == null) {
      setState(() {
        locating = false;
        locationStatusMessage = l10n.t('couldNotGetLocation');
      });
      return;
    }

    final updated = await widget.viewModel.updateHouseLocation(location);
    if (!mounted) return;
    setState(() {
      locating = false;
      locationStatusMessage = updated
          ? l10n.t('houseLocationUpdated')
          : widget.viewModel.errorMessage ??
              l10n.t('couldNotUpdateHouseLocation');
    });
  }

  Future<void> _updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    await widget.viewModel.updateNotificationPreferences(preferences);
  }

  Future<void> _pickBirthday() async {
    final user = widget.viewModel.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDate:
          user.birthDate ?? DateTime(now.year - 18, now.month, now.day),
    );
    if (picked == null) return;

    await _saveBirthday(DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _clearBirthday() => _saveBirthday(null);

  Future<void> _saveBirthday(DateTime? birthDate) async {
    final l10n = context.l10n;
    setState(() => updatingBirthday = true);
    final saved = await widget.viewModel.updateMyBirthDate(birthDate);
    if (!mounted) return;
    setState(() => updatingBirthday = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? birthDate == null
                ? l10n.t('birthdayRemoved')
                : l10n.t('birthdaySaved')
            : widget.viewModel.errorMessage ?? l10n.t('couldNotSaveBirthday')),
      ),
    );
  }

  Future<void> _toggleContinuousLocationUpdates(bool enabled) async {
    final l10n = context.l10n;
    if (!enabled) {
      await widget.viewModel.setContinuousLocationUpdates(false);
      if (mounted) setState(() => locationStatusMessage = null);
      return;
    }

    final serviceEnabled = await locationService.isLocationServiceEnabled();
    if (!serviceEnabled && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.t('enableLocation')),
          content: Text(l10n.t('enableAutoStatusLocationBody')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.t('ok')))
          ],
        ),
      );
      return;
    }

    setState(() => locating = true);
    final updated = await widget.viewModel.setContinuousLocationUpdates(true);
    if (!mounted) return;
    if (!updated) {
      await widget.viewModel.setContinuousLocationUpdates(false);
    }
    setState(() {
      locating = false;
      locationStatusMessage = updated
          ? l10n.t('continuousUpdatesEnabled')
          : l10n.t('couldNotEnableContinuousUpdates');
    });
  }

  void _showShortcutSheet({QuickShortcut? shortcut}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShortcutEditor(
        viewModel: widget.viewModel,
        shortcut: shortcut,
      ),
    );
  }

  void _openShortcuts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShortcutsScreen(viewModel: widget.viewModel),
      ),
    );
  }

  void _openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AboutScreen(viewModel: widget.viewModel),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(viewModel: widget.viewModel),
      ),
    );
  }

  Future<void> _showChangeHouseDialog() async {
    final result = await showDialog<_HouseChangeResult>(
      context: context,
      barrierDismissible: !widget.viewModel.isBusy,
      builder: (context) => _ChangeHouseDialog(viewModel: widget.viewModel),
    );
    if (!mounted) return;
    if (result == _HouseChangeResult.createNew) {
      await _showCreateHouseDialog();
      return;
    }
    if (result == _HouseChangeResult.chooseExisting) {
      await _openExistingHouseChooser();
      return;
    }
    if (result != _HouseChangeResult.changed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('houseChanged'))),
    );
  }

  Future<void> _openExistingHouseChooser() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HouseSelectionScreen(
          viewModel: widget.viewModel,
          showSignOut: false,
          popOnSuccess: true,
          onHouseSelected: (house) =>
              widget.viewModel.selectHouse(house, markOutside: true),
        ),
      ),
    );
    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('houseChanged'))),
    );
  }

  Future<void> _showCreateHouseDialog() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !widget.viewModel.isBusy,
      builder: (context) => _CreateHouseDialog(viewModel: widget.viewModel),
    );
    if (!mounted || created != true) return;
    final specialNumber = widget.viewModel.house?.specialNumber;
    if (specialNumber?.isNotEmpty == true) {
      await showHouseQrDialog(context, specialNumber!);
    }
  }

  Future<void> _deleteShortcut(QuickShortcut shortcut) async {
    final confirmed = await _confirmDeleteShortcut(shortcut);
    if (!confirmed || !mounted) return;

    setState(() => deletingShortcutId = shortcut.id);
    final deleted = await widget.viewModel.deleteShortcut(shortcut);
    if (!mounted) return;

    setState(() => deletingShortcutId = null);
    if (deleted) {
      return;
    }
    _showError(widget.viewModel.errorMessage ??
        context.l10n.t('couldNotDeleteShortcut'));
  }

  Future<bool> _confirmDeleteShortcut(QuickShortcut shortcut) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('deleteShortcutQuestion')),
        content: Text(l10n.tr('deleteShortcutBody', {'label': shortcut.label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyHouseSpecialNumber(String specialNumber) async {
    await Clipboard.setData(ClipboardData(text: specialNumber));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('houseSpecialNumberCopied'))),
    );
  }

  String _shortcutSubtitle(QuickShortcut shortcut) {
    return switch (shortcut.type) {
      ShortcutType.appMessage =>
        context.l10n.tr('familyChatValue', {'value': shortcut.value}),
      ShortcutType.sms => shortcut.value,
      ShortcutType.call => shortcut.value,
    };
  }
}

enum _HouseChangeResult { changed, createNew, chooseExisting }

class _ChangeHouseDialog extends StatefulWidget {
  final AppViewModel viewModel;

  const _ChangeHouseDialog({required this.viewModel});

  @override
  State<_ChangeHouseDialog> createState() => _ChangeHouseDialogState();
}

class _ChangeHouseDialogState extends State<_ChangeHouseDialog> {
  final houseCode = TextEditingController();
  late String relation =
      familyRelations.contains(widget.viewModel.currentUser?.relation)
          ? widget.viewModel.currentUser!.relation
          : familyRelations.first;
  String? localError;
  bool changing = false;

  @override
  void dispose() {
    houseCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(l10n.t('changeHouse')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t('changeHouseInfo')),
            const SizedBox(height: 14),
            TextField(
              controller: houseCode,
              textCapitalization: TextCapitalization.characters,
              enabled: !changing,
              decoration: InputDecoration(
                labelText: l10n.t('houseSpecialNumber'),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: changing ? null : _scanHouseCode,
              icon: const Icon(Icons.qr_code_scanner_outlined),
              label: Text(l10n.t('scanHouseQr')),
            ),
            if (widget.viewModel.availableHouses.length > 1) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: changing
                    ? null
                    : () => Navigator.pop(
                          context,
                          _HouseChangeResult.chooseExisting,
                        ),
                icon: const Icon(Icons.home_work_outlined),
                label: Text(l10n.t('chooseFromMyHouses')),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: relation,
              decoration: InputDecoration(labelText: l10n.t('yourFamilyRole')),
              items: familyRelations
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(l10n.relation(item)),
                      ))
                  .toList(),
              onChanged: changing
                  ? null
                  : (value) => setState(() => relation = value ?? relation),
            ),
            if (localError != null) ...[
              const SizedBox(height: 10),
              Text(
                localError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: changing ? null : () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        TextButton(
          onPressed: changing
              ? null
              : () => Navigator.pop(context, _HouseChangeResult.createNew),
          child: Text(l10n.t('createNewHouse')),
        ),
        FilledButton.icon(
          onPressed: changing ? null : _confirmAndChangeHouse,
          icon: changing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.swap_horiz_outlined),
          label: Text(
            changing ? l10n.t('changingHouse') : l10n.t('changeHouse'),
          ),
        ),
      ],
    );
  }

  Future<void> _scanHouseCode() async {
    final code = await scanHouseQrCode(context);
    if (!mounted || code == null) return;
    setState(() {
      houseCode.text = code;
      localError = null;
    });
  }

  Future<void> _confirmAndChangeHouse() async {
    final l10n = context.l10n;
    final code = houseCode.text.trim();
    if (code.isEmpty) {
      setState(() => localError = l10n.t('enterHouseSpecialNumber'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('changeHouseQuestion')),
        content: Text(l10n.t('changeHouseConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('changeHouse')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      changing = true;
      localError = null;
    });
    final changed = await widget.viewModel.changeHouse(
      houseCode: code,
      relation: relation,
    );
    if (!mounted) return;
    if (changed) {
      Navigator.pop(context, _HouseChangeResult.changed);
      return;
    }
    setState(() {
      changing = false;
      localError =
          widget.viewModel.errorMessage ?? l10n.t('couldNotChangeHouse');
    });
  }
}

class _CreateHouseDialog extends StatefulWidget {
  final AppViewModel viewModel;

  const _CreateHouseDialog({required this.viewModel});

  @override
  State<_CreateHouseDialog> createState() => _CreateHouseDialogState();
}

class _CreateHouseDialogState extends State<_CreateHouseDialog> {
  final houseName = TextEditingController(text: 'Our home');
  final address = TextEditingController();
  late String relation =
      familyRelations.contains(widget.viewModel.currentUser?.relation)
          ? widget.viewModel.currentUser!.relation
          : familyRelations.first;
  String? localError;
  bool creating = false;

  @override
  void dispose() {
    houseName.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(l10n.t('createNewHouse')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: houseName,
              enabled: !creating,
              decoration: InputDecoration(labelText: l10n.t('houseName')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: address,
              enabled: !creating,
              decoration:
                  InputDecoration(labelText: l10n.t('addressOrNeighborhood')),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: relation,
              decoration: InputDecoration(labelText: l10n.t('yourFamilyRole')),
              items: familyRelations
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(l10n.relation(item)),
                      ))
                  .toList(),
              onChanged: creating
                  ? null
                  : (value) => setState(() => relation = value ?? relation),
            ),
            if (localError != null) ...[
              const SizedBox(height: 10),
              Text(
                localError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: creating ? null : () => Navigator.pop(context, false),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: creating ? null : _createHouse,
          icon: creating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.home_work_outlined),
          label: Text(creating ? l10n.t('creating') : l10n.t('createHouse')),
        ),
      ],
    );
  }

  Future<void> _createHouse() async {
    final l10n = context.l10n;
    setState(() {
      creating = true;
      localError = null;
    });
    final created = await widget.viewModel.createHouse(
      name: houseName.text.trim().isEmpty
          ? l10n.t('defaultHouseName')
          : houseName.text.trim(),
      address: address.text.trim(),
      location: null,
      relation: relation,
      markOutside: true,
    );
    if (!mounted) return;
    if (created) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      creating = false;
      localError =
          widget.viewModel.errorMessage ?? l10n.t('couldNotCreateHouse');
    });
  }
}

class _SettingsTitleBar extends StatelessWidget {
  final String title;
  final String initial;
  final VoidCallback onProfileTap;

  const _SettingsTitleBar({
    required this.title,
    required this.initial,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFFDF8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.settings_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Tooltip(
          message: context.l10n.t('profile'),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onProfileTap,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFF97316),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final String name;
  final String houseName;
  final bool outsideHouse;

  const _SettingsHeader({
    required this.name,
    required this.houseName,
    required this.outsideHouse,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        outsideHouse ? const Color(0xFFB45309) : const Color(0xFF047857);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFFDF8), Color(0xFFE0F2FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Icon(
                outsideHouse ? Icons.directions_walk : Icons.home_outlined,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(houseName),
                  const SizedBox(height: 8),
                  Text(
                    outsideHouse
                        ? context.l10n.t('outside')
                        : context.l10n.t('inside'),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String iconAsset;
  final Color iconColor;
  final Color color;
  final String? info;
  final Widget? trailing;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.iconAsset,
    required this.iconColor,
    required this.color,
    required this.children,
    this.info,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: _SettingsSvgIcon(
                  assetName: iconAsset,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (info != null)
              IconButton(
                tooltip: context.l10n.tr('aboutSection', {'title': title}),
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.info_outline, size: 18, color: iconColor),
                onPressed: () => _showInfo(context),
              ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: ListTileTheme(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            minLeadingWidth: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _separatedChildren(context),
            ),
          ),
        ),
      ],
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
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
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: _SettingsSvgIcon(
                  assetName: iconAsset,
                  color: iconColor,
                  size: 20,
                ),
              ),
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
          info!,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('gotIt')),
          ),
        ],
      ),
    );
  }

  List<Widget> _separatedChildren(BuildContext context) {
    final separated = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        separated.add(
          Divider(
            height: 1,
            thickness: 0.6,
            indent: 12,
            endIndent: 12,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        );
      }
      separated.add(children[index]);
    }
    return separated;
  }
}

class _SettingsSvgIcon extends StatelessWidget {
  final String assetName;
  final Color color;
  final double size;

  const _SettingsSvgIcon({
    required this.assetName,
    required this.color,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
