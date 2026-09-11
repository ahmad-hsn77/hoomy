import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/chat_message.dart';
import '../../view_models/app_view_model.dart';

class MessageInfoScreen extends StatelessWidget {
  const MessageInfoScreen({
    super.key,
    required this.viewModel,
    required this.initialMessage,
  });

  final AppViewModel viewModel;
  final ChatMessage initialMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (context, _) {
        final message = viewModel.messages.firstWhere(
          (item) => item.id == initialMessage.id,
          orElse: () => initialMessage,
        );
        return _MessageInfoContent(viewModel: viewModel, message: message);
      },
    );
  }
}

class _MessageInfoContent extends StatelessWidget {
  const _MessageInfoContent({
    required this.viewModel,
    required this.message,
  });

  final AppViewModel viewModel;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final members = viewModel.members
        .where((member) => member.id != message.senderId)
        .toList();
    final seenMembers =
        members.where((member) => message.seenBy.contains(member.id)).toList();
    final deliveredMembers = members
        .where((member) =>
            message.receivedBy.contains(member.id) &&
            !message.seenBy.contains(member.id))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          style: IconButton.styleFrom(
                            fixedSize: const Size(40, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.t('messageInfo'),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: const Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tr('sentAt', {
                                  'time': DateFormat(
                                    'MMM d, h:mm a',
                                    l10n.localeName,
                                  ).format(message.createdAt.toLocal()),
                                }),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF64748B),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MessagePreviewCard(message: message),
                  const SizedBox(height: 24),
                  _MessageInfoSection(
                    icon: Icons.visibility_rounded,
                    iconColor: const Color(0xFF22C55E),
                    title: l10n.t('readBy'),
                    emptyText: l10n.t('notSeenYet'),
                    members: seenMembers,
                    statusText: l10n.t('read'),
                  ),
                  const SizedBox(height: 24),
                  _MessageInfoSection(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: const Color(0xFF64748B),
                    title: l10n.t('deliveredTo'),
                    emptyText: l10n.t('notDeliveredYet'),
                    members: deliveredMembers,
                    statusText: l10n.t('delivered'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePreviewCard extends StatelessWidget {
  const _MessagePreviewCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.audio
                ? l10n.tr('voiceMessageSeconds', {
                    'seconds': message.audioDurationSeconds ?? 0,
                  })
                : message.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(
                Icons.done_all_rounded,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                DateFormat('h:mm a', l10n.localeName)
                    .format(message.createdAt.toLocal()),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageInfoSection extends StatelessWidget {
  const _MessageInfoSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.emptyText,
    required this.members,
    required this.statusText,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String emptyText;
  final List<AppUser> members;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: members.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var index = 0; index < members.length; index++) ...[
                      _MessageInfoMemberChip(
                        member: members[index],
                        statusText: statusText,
                      ),
                      if (index != members.length - 1)
                        const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _MessageInfoMemberChip extends StatelessWidget {
  const _MessageInfoMemberChip({
    required this.member,
    required this.statusText,
  });

  final AppUser member;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = member.name.trim().isEmpty
        ? '?'
        : member.name.trim().characters.first.toUpperCase();
    final inside = !member.outsideHouse;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: inside ? const Color(0xFF14B8A6) : const Color(0xFFF59E0B),
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${member.name} (${member.relation})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: inside
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
