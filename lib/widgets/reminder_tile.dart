import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/localization/app_localizations.dart';
import '../models/family_reminder.dart';

class ReminderTile extends StatelessWidget {
  final FamilyReminder reminder;
  final Widget? trailing;

  const ReminderTile({super.key, required this.reminder, this.trailing});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metadata = [
      DateFormat('MMM d', l10n.localeName).format(reminder.dueAt),
      _timeLabel(context),
      _recurrenceLabel(context),
      if (reminder.isBirthday) l10n.t('birthdayReminder'),
    ].join(' - ');
    final iconColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                reminder.isBirthday
                    ? Icons.cake_rounded
                    : Icons.event_available_rounded,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFF64748B),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF64748B),
                                    height: 1.4,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (reminder.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      reminder.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            height: 1.35,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 16),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }

  String _timeLabel(BuildContext context) {
    final l10n = context.l10n;
    final formatter = DateFormat('h:mm a', l10n.localeName);
    return reminder.effectiveRingTimes
        .map((time) => formatter.format(reminder.scheduledAtForRingTime(time)))
        .join(', ');
  }

  String _recurrenceLabel(BuildContext context) {
    final l10n = context.l10n;
    if (reminder.repeatsDaily) return l10n.t('repeatDaily');
    if (reminder.repeatsWeekly) {
      final days = reminder.effectiveWeekdays;
      if (days.isEmpty) return l10n.t('repeatSelectedDays');
      final base = DateTime(2024, 1, 1);
      return days
          .map((day) => DateFormat('EEE', l10n.localeName)
              .format(base.add(Duration(days: day - 1))))
          .join(', ');
    }
    return l10n.t('repeatOnce');
  }
}
