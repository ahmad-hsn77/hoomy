import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/family_relations.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/calendar_utils.dart';
import '../../models/app_user.dart';
import '../../models/family_reminder.dart';
import '../../models/house.dart';
import '../../models/need_alert.dart';
import '../../models/quick_shortcut.dart';
import '../../view_models/app_view_model.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/reminder_tile.dart';
import '../settings/widgets/shortcut_editor.dart';
import 'widgets/alert_editor.dart';
import 'widgets/member_editor.dart';
import 'widgets/reminder_editor.dart';

class HomeScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const HomeScreen({
    super.key,
    required this.viewModel,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final Set<String> _selectedAlertIds = {};
  late final AnimationController _birthdayController;
  late final AnimationController _balloonController;
  late final Animation<double> _birthdayBounce;

  AppViewModel get viewModel => widget.viewModel;

  bool get _isSelectingAlerts => _selectedAlertIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _birthdayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _balloonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6800),
    )..repeat();
    _birthdayBounce = CurvedAnimation(
      parent: _birthdayController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _balloonController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedAlerts = viewModel.openAlerts
        .where((alert) => _selectedAlertIds.contains(alert.id))
        .toList();
    final birthdayNames = _birthdayNamesToday();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAlertSheet(context),
        icon: const Icon(Icons.add_alert_outlined),
        label: Text(l10n.t('needAlert')),
      ),
      body: Stack(
        children: [
          _HomeBackgroundDecorations(
            animation: _balloonController,
            showBalloons: birthdayNames.isNotEmpty,
          ),
          RefreshIndicator(
            onRefresh: () => _refreshHome(context),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 18, bottom: 116),
              children: [
                _HeroPanel(
                  viewModel: viewModel,
                  birthdayNames: birthdayNames,
                  birthdayAnimation: _birthdayBounce,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashboardSectionHeader(
                        title: l10n.t('quickActions'),
                        info: l10n.t('quickActionsInfo'),
                        infoIcon: Icons.bolt_outlined,
                        action: l10n.t('new'),
                        actionIcon: Icons.add_link_rounded,
                        onTap: () => _showShortcutSheet(context),
                      ),
                      if (viewModel.isLoadingShortcuts)
                        const _SectionLoading()
                      else
                        _ShortcutPanel(
                          shortcuts: viewModel.shortcuts,
                          viewModel: viewModel,
                          onAdd: () => _showShortcutSheet(context),
                        ),
                      const SizedBox(height: 22),
                      _DashboardSectionHeader(
                        title: l10n.t('needsAlerts'),
                        info: l10n.t('needsAlertsInfo'),
                        infoIcon: Icons.notifications_active_outlined,
                        action: _isSelectingAlerts
                            ? l10n.t('cancel')
                            : l10n.t('new'),
                        actionIcon: _isSelectingAlerts
                            ? Icons.close_rounded
                            : Icons.add_alert_rounded,
                        onTap: _isSelectingAlerts
                            ? () => setState(_selectedAlertIds.clear)
                            : () => _showAlertSheet(context),
                      ),
                      if (viewModel.openAlerts.length > 1 ||
                          _isSelectingAlerts) ...[
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  if (_selectedAlertIds.length ==
                                      viewModel.openAlerts.length) {
                                    _selectedAlertIds.clear();
                                  } else {
                                    _selectedAlertIds
                                      ..clear()
                                      ..addAll(viewModel.openAlerts
                                          .map((alert) => alert.id));
                                  }
                                });
                              },
                              icon: Icon(_selectedAlertIds.length ==
                                      viewModel.openAlerts.length
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank),
                              label: Text(_selectedAlertIds.length ==
                                      viewModel.openAlerts.length
                                  ? l10n.t('clearSelection')
                                  : l10n.t('selectNeeds')),
                            ),
                            const Spacer(),
                            if (_isSelectingAlerts)
                              FilledButton.icon(
                                onPressed: () => _showMultiBoughtSheet(
                                    context, selectedAlerts),
                                icon: const Icon(Icons.shopping_bag_outlined),
                                label: Text(l10n.tr('boughtCount',
                                    {'count': selectedAlerts.length})),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (viewModel.isLoadingAlerts)
                        const _SectionLoading()
                      else if (viewModel.openAlerts.isEmpty)
                        EmptyState(
                            icon: Icons.inventory_2_outlined,
                            text: l10n.t('noMissingItems'))
                      else
                        ...viewModel.openAlerts.map((alert) => _AlertTile(
                              viewModel: viewModel,
                              alert: alert,
                              selected: _selectedAlertIds.contains(alert.id),
                              selectionMode: _isSelectingAlerts,
                              onSelectedChanged: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedAlertIds.add(alert.id);
                                  } else {
                                    _selectedAlertIds.remove(alert.id);
                                  }
                                });
                              },
                            )),
                      const SizedBox(height: 22),
                      _DashboardSectionHeader(
                        title: l10n.t('reminders'),
                        info: l10n.t('remindersInfo'),
                        infoIcon: Icons.event_available_outlined,
                        action: l10n.t('new'),
                        actionIcon: Icons.alarm_add_rounded,
                        onTap: () => _showReminderSheet(context),
                      ),
                      if (viewModel.isLoadingReminders)
                        const _SectionLoading()
                      else
                        ...viewModel.reminders.take(4).map((item) =>
                            ReminderTile(
                              reminder: item,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: l10n.t('updateReminder'),
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      fixedSize: const Size(32, 32),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () => _showReminderSheet(context,
                                        reminder: item),
                                    icon: Icon(
                                      Icons.edit_rounded,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      size: 16,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l10n.t('deleteReminder'),
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      fixedSize: const Size(32, 32),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () =>
                                        _deleteReminder(context, item),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFDC2626),
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      const SizedBox(height: 22),
                      _DashboardSectionHeader(
                        title: l10n.t('family'),
                        info: l10n.t('familyInfo'),
                        infoIcon: Icons.family_restroom,
                        action: l10n.t('new'),
                        actionIcon: Icons.person_add_alt_1_rounded,
                        onTap: () => _showMemberSheet(context),
                      ),
                      if (viewModel.isLoadingMembers)
                        const _SectionLoading()
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: viewModel.members
                              .map((member) => _MemberTile(
                                    member: member,
                                    relation: relationshipLabelFor(
                                      currentUserRelation:
                                          viewModel.currentUser?.relation ??
                                              l10n.t('member'),
                                      memberRelation: member.relation,
                                      isCurrentUser: member.id ==
                                          viewModel.currentUser?.id,
                                    ),
                                    onTap: () => _showMemberLocationDialog(
                                        context, member),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshHome(BuildContext context) async {
    final refreshed = await viewModel.refreshHouseState();
    if (!refreshed && context.mounted) {
      _showError(context, viewModel.errorMessage);
    }
  }

  void _showAlertSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AlertEditor(viewModel: viewModel),
    );
  }

  void _showReminderSheet(BuildContext context, {FamilyReminder? reminder}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReminderEditor(viewModel: viewModel, reminder: reminder),
    );
  }

  Future<void> _deleteReminder(
      BuildContext context, FamilyReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('deleteReminderQuestion')),
        content: Text(
          context.l10n.tr('deleteReminderBody', {'title': reminder.title}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await viewModel.deleteReminder(reminder);
    if (!deleted && context.mounted) {
      _showError(context, viewModel.errorMessage);
    }
  }

  void _showMemberSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MemberEditor(viewModel: viewModel),
    );
  }

  void _showMemberLocationDialog(BuildContext context, AppUser member) {
    final l10n = context.l10n;
    final location = member.lastLocation;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(l10n.t('memberLocation')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(nameInitial(member.name))),
              title: Text(member.name),
              subtitle: Text(
                member.outsideHouse ? l10n.t('outside') : l10n.t('inside'),
              ),
            ),
            const Divider(),
            if (location == null)
              Text(l10n.t('locationNotAvailableBody'))
            else ...[
              _LocationInfoRow(
                label: l10n.t('latitude'),
                value: location.lat.toStringAsFixed(6),
              ),
              _LocationInfoRow(
                label: l10n.t('longitude'),
                value: location.lng.toStringAsFixed(6),
              ),
              _LocationInfoRow(
                label: l10n.t('lastUpdated'),
                value: member.locationStatusUpdatedAt == null
                    ? l10n.t('notUpdatedYet')
                    : DateFormat('EEE, MMM d - h:mm a', l10n.localeName)
                        .format(member.locationStatusUpdatedAt!),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
          if (location != null)
            FilledButton.icon(
              onPressed: () => _openGoogleMaps(location),
              icon: const Icon(Icons.map_outlined),
              label: Text(l10n.t('openGoogleMaps')),
            ),
        ],
      ),
    );
  }

  Future<void> _openGoogleMaps(GeoPoint location) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${location.lat},${location.lng}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showShortcutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShortcutEditor(viewModel: viewModel),
    );
  }

  List<String> _birthdayNamesToday() {
    final currentUser = viewModel.currentUser;
    if (currentUser == null) return const [];

    final now = DateTime.now();
    final names = <String>[];
    if (currentUser.birthDate != null &&
        _isSameBirthdayDay(currentUser.birthDate!, now)) {
      names.add(currentUser.name);
    }
    for (final reminder in viewModel.reminders) {
      if (!reminder.isBirthday ||
          reminder.birthdayMemberId != currentUser.id ||
          !_isSameBirthdayDay(reminder.dueAt, now)) {
        continue;
      }
      names.add(currentUser.name);
    }
    return names.toSet().toList();
  }

  bool _isSameBirthdayDay(DateTime birthday, DateTime today) {
    final localBirthday = birthday.toLocal();
    return localBirthday.month == today.month && localBirthday.day == today.day;
  }

  void _showMultiBoughtSheet(
      BuildContext context, List<NeedAlert> selectedAlerts) {
    final l10n = context.l10n;
    String? localError;
    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.t('markSelectedNeedsBought'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                selectedAlerts.map((alert) => alert.title).join(', '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (localError != null) ...[
                const SizedBox(height: 8),
                Text(localError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setSheetState(() {
                          localError = null;
                          isSaving = true;
                        });
                        final saved =
                            await viewModel.markAlertsBought(selectedAlerts);
                        if (saved && context.mounted) {
                          Navigator.pop(context);
                          setState(_selectedAlertIds.clear);
                          return;
                        }
                        if (context.mounted) {
                          setSheetState(() {
                            isSaving = false;
                            localError = viewModel.errorMessage ??
                                l10n.t('couldNotNotifyFamily');
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all),
                label: Text(
                    isSaving ? l10n.t('notifying') : l10n.t('notifyFamily')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBackgroundDecorations extends StatelessWidget {
  final Animation<double> animation;
  final bool showBalloons;

  const _HomeBackgroundDecorations({
    required this.animation,
    required this.showBalloons,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBalloons) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Positioned(
                top: 16,
                right: -28,
                child: _SoftCircle(
                  size: 104,
                  color: Color(0x33F9A8D4),
                ),
              ),
              const Positioned(
                top: 132,
                left: -36,
                child: _SoftCircle(
                  size: 88,
                  color: Color(0x332DD4BF),
                ),
              ),
              if (showBalloons) ...[
                _FloatingBalloonDecoration(
                  animation: animation,
                  availableHeight: constraints.maxHeight,
                  horizontalOffset: 24,
                  fromRight: true,
                  phase: 0,
                  color: const Color(0xFFFB7185),
                  scale: 0.9,
                ),
                _FloatingBalloonDecoration(
                  animation: animation,
                  availableHeight: constraints.maxHeight,
                  horizontalOffset: 18,
                  fromRight: false,
                  phase: 0.48,
                  color: const Color(0xFF38BDF8),
                  scale: 0.72,
                ),
              ],
              const Positioned(
                bottom: 112,
                right: -18,
                child: _SoftCircle(
                  size: 126,
                  color: Color(0x22FACC15),
                ),
              ),
              const Positioned(
                bottom: 220,
                left: 32,
                child: _TinySparkles(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FloatingBalloonDecoration extends StatelessWidget {
  final Animation<double> animation;
  final double availableHeight;
  final double horizontalOffset;
  final bool fromRight;
  final double phase;
  final Color color;
  final double scale;

  const _FloatingBalloonDecoration({
    required this.animation,
    required this.availableHeight,
    required this.horizontalOffset,
    required this.fromRight,
    required this.phase,
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    const balloonHeight = 82.0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = (animation.value + phase) % 1;
        final top =
            availableHeight - ((availableHeight + balloonHeight) * progress);
        final sideWave = 10 * (progress < 0.5 ? progress : 1 - progress);
        return Positioned(
          top: top,
          right: fromRight ? horizontalOffset + sideWave : null,
          left: fromRight ? null : horizontalOffset + sideWave,
          child: child!,
        );
      },
      child: _BalloonDecoration(
        color: color,
        scale: scale,
      ),
    );
  }
}

class _LocationInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _LocationInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _BalloonDecoration extends StatelessWidget {
  final Color color;
  final double scale;

  const _BalloonDecoration({
    required this.color,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              border:
                  Border.all(color: color.withValues(alpha: 0.52), width: 1.4),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
          ),
          Container(
            width: 1.4,
            height: 34,
            color: color.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

class _TinySparkles extends StatelessWidget {
  const _TinySparkles();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 74,
      height: 42,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 8,
            child: Icon(Icons.auto_awesome, size: 16, color: Color(0x99F59E0B)),
          ),
          Positioned(
            top: 18,
            right: 6,
            child: Icon(Icons.auto_awesome, size: 12, color: Color(0x998B5CF6)),
          ),
          Positioned(
            bottom: 0,
            left: 34,
            child: Icon(Icons.auto_awesome, size: 10, color: Color(0x9914B8A6)),
          ),
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    return Column(
      children: List.generate(
        2,
        (index) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: index == 0 ? 0.62 : 0.48,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FractionallySizedBox(
                      widthFactor: index == 0 ? 0.42 : 0.56,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String info;
  final IconData infoIcon;
  final String action;
  final IconData actionIcon;
  final VoidCallback onTap;

  const _DashboardSectionHeader({
    required this.title,
    required this.info,
    required this.infoIcon,
    required this.action,
    required this.actionIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                _TinyInfoButton(
                  title: title,
                  info: info,
                  icon: infoIcon,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(actionIcon, size: 16),
            label: Text(
              action,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyInfoButton extends StatelessWidget {
  final String title;
  final String info;
  final IconData icon;

  const _TinyInfoButton({
    required this.title,
    required this.info,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 14,
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFEFFDF8),
                  child:
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
              ],
            ),
            content: Text(info),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.t('ok')),
              ),
            ],
          ),
        );
      },
      child: Icon(
        Icons.info_outline_rounded,
        size: 13,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.72),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final AppViewModel viewModel;
  final List<String> birthdayNames;
  final Animation<double> birthdayAnimation;

  const _HeroPanel({
    required this.viewModel,
    required this.birthdayNames,
    required this.birthdayAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = viewModel.currentUser;
    final inside = user?.outsideHouse == false;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Color(0xFFF7FFFC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            viewModel.house?.name ?? l10n.t('hoomy'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF334155),
                                ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.house_rounded, size: 18),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('helloName', {
                        'name': user?.name ?? l10n.t('family'),
                      }),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: inside
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFF97316),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: Colors.white),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        inside ? l10n.t('inside') : l10n.t('outside'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.tr('homeSummary', {
                          'needs': viewModel.openAlerts.length,
                          'reminders': viewModel.reminders.length,
                          'members': viewModel.members.length,
                        }),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () async {
                    final updated = await viewModel
                        .refreshCurrentLocationStatusFromDevice();
                    if (!updated && context.mounted) {
                      _showError(
                          context, l10n.t('couldNotUpdateLocationStatus'));
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      l10n.t('update'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (viewModel.emergencyAlertCount > 0) ...[
            const SizedBox(height: 10),
            Chip(
              avatar: const Icon(Icons.priority_high, color: Colors.white),
              label: Text(l10n.tr('emergencyAlertCount',
                  {'count': viewModel.emergencyAlertCount})),
              backgroundColor: const Color(0xFFDC2626),
              labelStyle: const TextStyle(color: Colors.white),
            ),
          ],
          if (birthdayNames.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BirthdayTodayBanner(
              names: birthdayNames,
              animation: birthdayAnimation,
            ),
          ],
        ],
      ),
    );
  }
}

class _BirthdayTodayBanner extends StatelessWidget {
  final List<String> names;
  final Animation<double> animation;

  const _BirthdayTodayBanner({
    required this.names,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = names.length == 1
        ? l10n.tr('birthdayToday', {'name': names.first})
        : l10n.tr('birthdaysToday', {'names': names.join(', ')});
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -3 * animation.value),
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cake_outlined, size: 18, color: Color(0xFFEA580C)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF9A3412),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final AppUser member;
  final String relation;
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.relation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final outside = member.outsideHouse == true;
    final statusColor =
        outside ? const Color(0xFFB45309) : const Color(0xFF047857);
    final statusBackground =
        outside ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5);
    return Tooltip(
      message: l10n.t('viewMemberLocation'),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: statusBackground,
                child: Text(
                  nameInitial(member.name),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      relation,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                outside ? Icons.directions_walk : Icons.home_rounded,
                color: statusColor,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final AppViewModel viewModel;
  final NeedAlert alert;
  final bool selected;
  final bool selectionMode;
  final ValueChanged<bool> onSelectedChanged;

  const _AlertTile({
    required this.viewModel,
    required this.alert,
    required this.selected,
    required this.selectionMode,
    required this.onSelectedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final targets = alert.targetMemberIds.isEmpty
        ? l10n.t('autoMembersOutside')
        : viewModel.members
            .where((member) => alert.targetMemberIds.contains(member.id))
            .map((member) => member.name)
            .join(', ');
    final details = [
      if (alert.quantity.isNotEmpty) alert.quantity,
      targets,
      if (alert.note.isNotEmpty) alert.note,
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: () => onSelectedChanged(!selected),
        onTap: selectionMode
            ? () => onSelectedChanged(!selected)
            : () => _showNeedDetailsSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: alert.emergency
                      ? const Color(0xFFFFE4E6)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  alert.emergency
                      ? Icons.call_rounded
                      : Icons.shopping_basket_rounded,
                  color: alert.emergency
                      ? const Color(0xFFE11D48)
                      : const Color(0xFFF97316),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (alert.emergency)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4E6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              l10n.t('urgent'),
                              style: const TextStyle(
                                color: Color(0xFFE11D48),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details.join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              selectionMode
                  ? Checkbox(
                      value: selected,
                      onChanged: (value) => onSelectedChanged(value ?? false),
                    )
                  : IconButton.filledTonal(
                      onPressed: () => _showBoughtSheet(context),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      tooltip: l10n.t('bought'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNeedDetailsSheet(BuildContext context) {
    final parentContext = context;
    final l10n = context.l10n;
    final requester = viewModel.memberById(alert.createdBy)?.name ?? 'Family';
    final note = alert.note.trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  alert.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: const Color(0xFF0F172A),
                                        fontWeight: FontWeight.w900,
                                        height: 1.3,
                                      ),
                                ),
                              ),
                              if (alert.emergency) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE4E6),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    l10n.t('urgent'),
                                    style: const TextStyle(
                                      color: Color(0xFF9F1239),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Requested by $requester - ${_relativeCreatedAt(context)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF64748B),
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: IconButton.styleFrom(
                        fixedSize: const Size(40, 40),
                        backgroundColor: const Color(0xFFE2E8F0),
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (note.isNotEmpty) ...[
                  _NeedInfoPanel(
                    icon: Icons.description_rounded,
                    child: Text(
                      note,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF0F172A),
                            height: 1.5,
                          ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _NeedMetricCard(
                        label: 'Quantity',
                        value: alert.quantity.isEmpty ? '-' : alert.quantity,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _NeedMetricCard(
                        label: 'Recipients',
                        value: _targetLabel(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Future<void>.delayed(Duration.zero, () {
                      if (parentContext.mounted) {
                        _showBoughtSheet(parentContext);
                      }
                    });
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 24),
                  label: const Text('Mark as Bought'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBoughtSheet(BuildContext context) {
    final l10n = context.l10n;
    final quantity = TextEditingController();
    final price = TextEditingController();
    final canCancel = alert.createdBy == viewModel.currentUser?.id;
    String? localError;
    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.tr('markAsBought', {'item': alert.title}),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                  controller: quantity,
                  decoration:
                      InputDecoration(labelText: l10n.t('quantityOptional'))),
              const SizedBox(height: 8),
              TextField(
                  controller: price,
                  decoration:
                      InputDecoration(labelText: l10n.t('priceOptional'))),
              if (localError != null) ...[
                const SizedBox(height: 8),
                Text(localError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setSheetState(() {
                          localError = null;
                          isSaving = true;
                        });
                        final saved = await viewModel.markAlertBought(alert,
                            quantity: quantity.text.trim(),
                            price: price.text.trim());
                        if (saved && context.mounted) {
                          Navigator.pop(context);
                          return;
                        }
                        if (context.mounted) {
                          setSheetState(() {
                            isSaving = false;
                            localError = viewModel.errorMessage ??
                                l10n.t('couldNotNotifyFamily');
                          });
                        }
                      },
                icon: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_bag_outlined),
                label: Text(
                    isSaving ? l10n.t('notifying') : l10n.t('notifyFamily')),
              ),
              if (canCancel) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setSheetState(() {
                            localError = null;
                            isSaving = true;
                          });
                          final deleted = await viewModel.deleteAlert(alert);
                          if (deleted && context.mounted) {
                            Navigator.pop(context);
                            return;
                          }
                          if (context.mounted) {
                            setSheetState(() {
                              isSaving = false;
                              localError = viewModel.errorMessage ??
                                  l10n.t('requestFailed');
                            });
                          }
                        },
                  icon: isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined),
                  label: Text(l10n.t('cancel')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _targetLabel(BuildContext context) {
    final l10n = context.l10n;
    if (alert.targetMemberIds.isEmpty) return l10n.t('autoMembersOutside');
    final names = viewModel.members
        .where((member) => alert.targetMemberIds.contains(member.id))
        .map((member) => member.name)
        .toList();
    return names.isEmpty ? l10n.t('autoMembersOutside') : names.join(', ');
  }

  String _relativeCreatedAt(BuildContext context) {
    final l10n = context.l10n;
    final difference = DateTime.now().difference(alert.createdAt);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    }
    if (difference.inDays < 1) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    }
    return DateFormat('MMM d, h:mm a', l10n.localeName).format(alert.createdAt);
  }
}

class _NeedInfoPanel extends StatelessWidget {
  final IconData icon;
  final Widget child;

  const _NeedInfoPanel({
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF0F172A), size: 24),
          const SizedBox(width: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NeedMetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _NeedMetricCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF64748B),
                  height: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, String? message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message ?? context.l10n.t('requestFailed'))),
  );
}

class _ShortcutPanel extends StatelessWidget {
  final List<QuickShortcut> shortcuts;
  final AppViewModel viewModel;
  final VoidCallback onAdd;

  const _ShortcutPanel({
    required this.shortcuts,
    required this.viewModel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _AddShortcutTile(onTap: onAdd),
            for (final shortcut in shortcuts) ...[
              const SizedBox(width: 14),
              _ShortcutChip(
                viewModel: viewModel,
                shortcut: shortcut,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddShortcutTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddShortcutTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_rounded, color: Color(0xFFF97316)),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('add'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  final AppViewModel viewModel;
  final QuickShortcut shortcut;

  const _ShortcutChip({required this.viewModel, required this.shortcut});

  @override
  Widget build(BuildContext context) {
    final icon = switch (shortcut.type) {
      ShortcutType.call => Icons.call,
      ShortcutType.sms => Icons.sms_outlined,
      ShortcutType.appMessage => Icons.send_outlined,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        if (shortcut.type == ShortcutType.appMessage) {
          final sent = await viewModel.sendMessage(
              shortcut.value.isEmpty ? shortcut.label : shortcut.value);
          if (!sent && context.mounted) {
            _showError(context, viewModel.errorMessage);
          }
          return;
        }
        final phone = _phoneShortcutValue(shortcut.value);
        final uri = shortcut.type == ShortcutType.call
            ? Uri(scheme: 'tel', path: phone)
            : Uri.parse('smsto:$phone');
        try {
          final launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched && context.mounted) {
            _showError(context, 'No app found to open this shortcut.');
          }
        } catch (_) {
          if (context.mounted) {
            _showError(context, 'Could not open this shortcut.');
          }
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _shortcutColor(shortcut.type).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: _shortcutColor(shortcut.type)),
            ),
            const SizedBox(height: 8),
            Text(
              shortcut.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _phoneShortcutValue(String value) {
    return value.trim().replaceAll(RegExp(r'[\s()-]'), '');
  }

  Color _shortcutColor(ShortcutType type) {
    return switch (type) {
      ShortcutType.call => const Color(0xFF0EA5E9),
      ShortcutType.sms => const Color(0xFF10B981),
      ShortcutType.appMessage => const Color(0xFF14B8A6),
    };
  }
}
