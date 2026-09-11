import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/calendar_utils.dart';
import '../../view_models/app_view_model.dart';
import '../../widgets/reminder_tile.dart';

class CalendarScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const CalendarScreen({super.key, required this.viewModel});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = visibleMonthDays(month);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy', l10n.localeName)
                              .format(month),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.t('hoomy')} · ${widget.viewModel.house?.name ?? l10n.t('house')}',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(
                        () => month = DateTime(month.year, month.month - 1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => setState(
                        () => month = DateTime(month.year, month.month + 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: days.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8),
                  itemBuilder: (context, index) {
                    final day = days[index];
                    final hasReminder = widget.viewModel.reminders
                        .any((item) => isSameDay(item.dueAt, day));
                    final hasAlert = widget.viewModel.alerts
                        .any((item) => isSameDay(item.createdAt, day));
                    final inMonth = day.month == month.month;
                    return Container(
                      decoration: BoxDecoration(
                        color: hasAlert
                            ? const Color(0xFFFFF7ED)
                            : hasReminder
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: inMonth
                                ? const Color(0xFFE2E8F0)
                                : Colors.transparent),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${day.day}',
                                style: TextStyle(
                                    color: inMonth
                                        ? const Color(0xFF0F172A)
                                        : const Color(0xFFCBD5E1),
                                    fontWeight: FontWeight.w800)),
                            if (hasAlert || hasReminder)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: hasAlert
                                      ? const Color(0xFFF97316)
                                      : const Color(0xFF2563EB),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(l10n.t('thisMonth'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            child: Column(
              children: [
                ...widget.viewModel.reminders
                    .where((item) =>
                        item.dueAt.month == month.month &&
                        item.dueAt.year == month.year)
                    .map((item) => ReminderTile(reminder: item)),
                ...widget.viewModel.alerts
                    .where((item) =>
                        item.createdAt.month == month.month &&
                        item.createdAt.year == month.year)
                    .map((item) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFFFF7ED),
                              child: Icon(Icons.notifications_active_outlined,
                                  color: Color(0xFFF97316)),
                            ),
                            title: Text(item.title),
                            subtitle: Text(
                                DateFormat('MMM d - h:mm a', l10n.localeName)
                                    .format(item.createdAt)),
                          ),
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
