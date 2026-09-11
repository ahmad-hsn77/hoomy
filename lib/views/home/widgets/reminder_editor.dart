import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../../models/family_reminder.dart';
import '../../../view_models/app_view_model.dart';

class ReminderEditor extends StatefulWidget {
  final AppViewModel viewModel;
  final FamilyReminder? reminder;

  const ReminderEditor({super.key, required this.viewModel, this.reminder});

  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  late final TextEditingController title =
      TextEditingController(text: widget.reminder?.title ?? '');
  late final TextEditingController note =
      TextEditingController(text: widget.reminder?.note ?? '');
  late DateTime dueAt = widget.reminder?.dueAt ?? _defaultDueAt();
  late final List<TimeOfDay> ringTimes = _initialRingTimes();
  late bool isBirthday = widget.reminder?.isBirthday ?? false;
  late String? birthdayMemberId = widget.reminder?.birthdayMemberId;
  late String recurrence =
      widget.reminder?.recurrence ?? ReminderRecurrence.once;
  late final Set<int> recurrenceWeekdays =
      widget.reminder?.recurrenceWeekdays.toSet() ?? <int>{dueAt.weekday};
  String? localError;
  bool isSaving = false;

  DateTime _defaultDueAt() {
    final nextTime = DateTime.now().add(const Duration(minutes: 2));
    return DateTime(
      nextTime.year,
      nextTime.month,
      nextTime.day,
      nextTime.hour,
      nextTime.minute,
    );
  }

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.reminder != null;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final sheetMaxHeight =
        (media.size.height - media.padding.top - bottomInset - 12)
            .clamp(280.0, media.size.height * 0.92)
            .toDouble();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetMaxHeight),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(editing ? l10n.t('updateReminder') : l10n.t('addReminder'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                    controller: title,
                    decoration:
                        InputDecoration(labelText: l10n.t('reminderTitle'))),
                const SizedBox(height: 8),
                TextField(
                    controller: note,
                    decoration:
                        InputDecoration(labelText: l10n.t('noteOptional'))),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(
                      DateFormat('EEE, MMM d', l10n.localeName).format(dueAt)),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('ringTimes'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                ...ringTimes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final time = entry.value;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(time.format(context)),
                    onTap: () => _editRingTime(index),
                    trailing: ringTimes.length > 1
                        ? IconButton(
                            tooltip: l10n.t('removeTime'),
                            onPressed: () =>
                                setState(() => ringTimes.removeAt(index)),
                            icon: const Icon(Icons.close_rounded),
                          )
                        : null,
                  );
                }),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _addRingTime,
                    icon: const Icon(Icons.add_alarm_outlined),
                    label: Text(l10n.t('addAnotherTime')),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('repeatReminder'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.t('repeatOnce')),
                      selected: recurrence == ReminderRecurrence.once,
                      onSelected: (_) =>
                          _setRecurrence(ReminderRecurrence.once),
                    ),
                    ChoiceChip(
                      label: Text(l10n.t('repeatDaily')),
                      selected: recurrence == ReminderRecurrence.daily,
                      onSelected: (_) =>
                          _setRecurrence(ReminderRecurrence.daily),
                    ),
                    ChoiceChip(
                      label: Text(l10n.t('repeatSelectedDays')),
                      selected: recurrence == ReminderRecurrence.weekly,
                      onSelected: (_) =>
                          _setRecurrence(ReminderRecurrence.weekly),
                    ),
                  ],
                ),
                if (recurrence == ReminderRecurrence.weekly) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _weekdayValues.map((day) {
                      final selected = recurrenceWeekdays.contains(day);
                      return FilterChip(
                        label: Text(_weekdayLabel(day)),
                        selected: selected,
                        onSelected: (_) => _toggleWeekday(day),
                      );
                    }).toList(),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.cake_outlined),
                  title: Text(l10n.t('isBirthday')),
                  subtitle: Text(l10n.t('birthdayReminderInfo')),
                  value: isBirthday,
                  onChanged: (value) {
                    setState(() {
                      isBirthday = value;
                      if (!value) birthdayMemberId = null;
                    });
                  },
                ),
                if (isBirthday) ...[
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: birthdayMemberId,
                    decoration: InputDecoration(
                      labelText: l10n.t('birthdayFamilyMember'),
                    ),
                    items: widget.viewModel.members
                        .map((member) => DropdownMenuItem(
                              value: member.id,
                              child: Text(member.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => birthdayMemberId = value),
                  ),
                ],
                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Text(localError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: isSaving ? null : _save,
                  icon: isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(editing
                          ? Icons.check
                          : Icons.event_available_outlined),
                  label: Text(isSaving
                      ? l10n.t('saving')
                      : editing
                          ? l10n.t('updateReminder')
                          : l10n.t('saveReminder')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final firstDate = isBirthday ? DateTime(1900) : now;
    final lastDate = isBirthday
        ? DateTime(now.year + 1, 12, 31)
        : now.add(const Duration(days: 365));
    final initialDate = dueAt.isBefore(firstDate)
        ? firstDate
        : dueAt.isAfter(lastDate)
            ? lastDate
            : dueAt;
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: initialDate,
    );
    if (picked != null) {
      setState(() => dueAt = DateTime(
          picked.year, picked.month, picked.day, dueAt.hour, dueAt.minute));
    }
  }

  Future<void> _addRingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          ringTimes.isEmpty ? TimeOfDay.fromDateTime(dueAt) : ringTimes.last,
    );
    if (picked == null) return;
    if (_containsTime(picked)) {
      setState(() => localError = context.l10n.t('duplicateRingTime'));
      return;
    }
    setState(() {
      localError = null;
      ringTimes.add(picked);
      _sortRingTimes();
      _syncDueAtToFirstRingTime();
    });
  }

  Future<void> _editRingTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: ringTimes[index],
    );
    if (picked == null) return;
    if (_containsTime(picked, exceptIndex: index)) {
      setState(() => localError = context.l10n.t('duplicateRingTime'));
      return;
    }
    setState(() {
      localError = null;
      ringTimes[index] = picked;
      _sortRingTimes();
      _syncDueAtToFirstRingTime();
    });
  }

  Future<void> _save() async {
    final user = widget.viewModel.currentUser;
    if (user == null) return;

    final selectedBirthdayMember =
        isBirthday ? _memberById(birthdayMemberId) : null;
    final reminderTitle = title.text.trim().isEmpty &&
            selectedBirthdayMember != null
        ? context.l10n
            .tr('memberBirthdayTitle', {'name': selectedBirthdayMember.name})
        : title.text.trim();
    if (reminderTitle.isEmpty) {
      setState(() => localError = context.l10n.t('addReminderTitle'));
      return;
    }
    if (isBirthday && selectedBirthdayMember == null) {
      setState(() => localError = context.l10n.t('chooseBirthdayMember'));
      return;
    }
    if (recurrence == ReminderRecurrence.weekly && recurrenceWeekdays.isEmpty) {
      setState(() => localError = context.l10n.t('chooseReminderDays'));
      return;
    }

    setState(() {
      localError = null;
      isSaving = true;
    });
    final reminder = FamilyReminder(
      id: widget.reminder?.id ?? widget.viewModel.nextId('r'),
      title: reminderTitle,
      note: note.text.trim(),
      dueAt: dueAt,
      ringTimes: _encodedRingTimes(),
      recurrence: recurrence,
      recurrenceWeekdays: _encodedWeekdays(),
      createdBy: widget.reminder?.createdBy ?? user.id,
      isBirthday: isBirthday,
      birthdayMemberId: isBirthday ? birthdayMemberId : null,
    );
    final saved = widget.reminder == null
        ? await widget.viewModel.addReminder(reminder)
        : await widget.viewModel.updateReminder(reminder);
    if (saved && mounted) {
      Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() {
        isSaving = false;
        localError = widget.viewModel.errorMessage ??
            context.l10n.t('couldNotSaveReminder');
      });
    }
  }

  AppUser? _memberById(String? memberId) {
    if (memberId == null) return null;
    for (final member in widget.viewModel.members) {
      if (member.id == memberId) return member;
    }
    return null;
  }

  static const _weekdayValues = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  void _setRecurrence(String value) {
    setState(() {
      recurrence = value;
      localError = null;
      if (recurrence == ReminderRecurrence.weekly &&
          recurrenceWeekdays.isEmpty) {
        recurrenceWeekdays.add(dueAt.weekday);
      }
    });
  }

  void _toggleWeekday(int day) {
    setState(() {
      localError = null;
      if (recurrenceWeekdays.contains(day)) {
        recurrenceWeekdays.remove(day);
      } else {
        recurrenceWeekdays.add(day);
      }
    });
  }

  String _weekdayLabel(int day) {
    final base = DateTime(2024, 1, 1).add(Duration(days: day - 1));
    return DateFormat.E(context.l10n.localeName).format(base);
  }

  List<int> _encodedWeekdays() {
    if (recurrence != ReminderRecurrence.weekly) return const [];
    final values = recurrenceWeekdays.toList()..sort();
    return values;
  }

  List<TimeOfDay> _initialRingTimes() {
    final reminder = widget.reminder;
    final encoded = reminder?.effectiveRingTimes ?? const <String>[];
    final parsed = encoded.map(_parseTimeOfDay).whereType<TimeOfDay>().toList();
    return parsed.isEmpty ? [TimeOfDay.fromDateTime(dueAt)] : parsed;
  }

  TimeOfDay? _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  bool _containsTime(TimeOfDay time, {int? exceptIndex}) {
    return ringTimes.asMap().entries.any((entry) {
      if (entry.key == exceptIndex) return false;
      return entry.value.hour == time.hour && entry.value.minute == time.minute;
    });
  }

  void _sortRingTimes() {
    ringTimes.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
  }

  void _syncDueAtToFirstRingTime() {
    final first = ringTimes.first;
    dueAt =
        DateTime(dueAt.year, dueAt.month, dueAt.day, first.hour, first.minute);
  }

  List<String> _encodedRingTimes() {
    _sortRingTimes();
    _syncDueAtToFirstRingTime();
    return ringTimes
        .map((time) =>
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}')
        .toList();
  }
}
