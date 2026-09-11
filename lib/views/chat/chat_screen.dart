import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/localization/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../view_models/app_view_model.dart';
import 'message_info_screen.dart';
import 'voice_recording_gesture.dart';

class ChatScreen extends StatefulWidget {
  final AppViewModel viewModel;

  const ChatScreen({super.key, required this.viewModel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _reactionEmojis = ['❤️', '😂', '👍', '🙏', '😮', '😢'];

  final controller = TextEditingController();
  final _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _imagePicker = ImagePicker();
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<void>? _audioCompleteSubscription;
  Timer? _recordingTimer;
  ChatMessage? replyingTo;
  ChatMessage? editingMessage;
  DateTime? _recordingStartedAt;
  String? _recordingPath;
  bool _recordingLocked = false;
  bool _recordingWillCancel = false;
  Offset _recordingDragDelta = Offset.zero;
  bool _recordingCancelHapticSent = false;
  bool _recordingLockHapticSent = false;
  String? _voicePreviewPath;
  int _voicePreviewDurationSeconds = 0;
  String? _playingMessageId;
  Duration _playbackPosition = Duration.zero;
  double _playbackSpeed = 1;

  bool get isRecording => _recordingStartedAt != null;
  bool get _hasMessageText => controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleComposerTextChanged);
    _scrollController.addListener(_handleMessageScroll);
    _audioPositionSubscription = _audioPlayer.onPositionChanged.listen((value) {
      if (!mounted || _playingMessageId == null) return;
      setState(() => _playbackPosition = value);
    });
    _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingMessageId = null;
        _playbackPosition = Duration.zero;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.viewModel.refreshChatMessages());
    });
  }

  @override
  void dispose() {
    controller.removeListener(_handleComposerTextChanged);
    controller.dispose();
    _scrollController.removeListener(_handleMessageScroll);
    _scrollController.dispose();
    _audioPositionSubscription?.cancel();
    _audioCompleteSubscription?.cancel();
    _recordingTimer?.cancel();
    final recordingPath = _recordingPath;
    final previewPath = _voicePreviewPath;
    if (recordingPath != null) {
      unawaited(_audioRecorder.cancel());
      unawaited(_deleteFileQuietly(recordingPath));
    }
    if (previewPath != null) {
      unawaited(_deleteFileQuietly(previewPath));
    }
    unawaited(_audioPlayer.stop());
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _handleComposerTextChanged() {
    if (mounted) setState(() {});
  }

  void _handleMessageScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 220) {
      unawaited(widget.viewModel.loadOlderChatMessages());
    }
  }

  Future<void> _deleteFileQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFFDF8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.chat_bubble_rounded,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('familyChat'),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.tr('homeSummary', {
                                'needs': widget.viewModel.openAlerts.length,
                                'reminders': widget.viewModel.reminders.length,
                                'members': widget.viewModel.members.length,
                              }),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: widget.viewModel.messages.isEmpty &&
                    widget.viewModel.isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : widget.viewModel.messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                                'assets/illustrations/chat_empty.svg',
                                height: 150),
                            const SizedBox(height: 12),
                            Text(l10n.t('noMessagesYet'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                        itemCount: widget.viewModel.messages.length +
                            (widget.viewModel.isLoadingOlderMessages ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == widget.viewModel.messages.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final message = widget.viewModel.messages[index];
                          final mine = message.senderId ==
                              widget.viewModel.currentUser?.id;
                          final sender =
                              widget.viewModel.memberById(message.senderId);
                          final replySender = message.replyToSenderId == null
                              ? null
                              : widget.viewModel
                                  .memberById(message.replyToSenderId!);
                          final status = message.deliveryStatusFor(
                              widget.viewModel.currentUser?.id);
                          final bubbleMaxWidth = message.image ? 360.0 : 320.0;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTapUp: (details) => _showMessageOptions(
                                    message,
                                    details.globalPosition,
                                    mine: mine,
                                  ),
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      bottom:
                                          message.reactions.isEmpty ? 10 : 0,
                                    ),
                                    padding:
                                        EdgeInsets.all(message.image ? 5 : 12),
                                    constraints: BoxConstraints(
                                      maxWidth: bubbleMaxWidth,
                                    ),
                                    decoration: BoxDecoration(
                                      color: message.system
                                          ? const Color(0xFFFFEDD5)
                                          : mine
                                              ? const Color(0xFFCCFBF1)
                                              : Colors.white,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(18),
                                        topRight: const Radius.circular(18),
                                        bottomLeft:
                                            Radius.circular(mine ? 18 : 4),
                                        bottomRight:
                                            Radius.circular(mine ? 4 : 18),
                                      ),
                                      border: Border.all(
                                          color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            message.system
                                                ? 'Hoomy'
                                                : sender?.name ??
                                                    l10n.t('member'),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        SizedBox(height: message.image ? 3 : 4),
                                        if ((message.replyToText ?? '')
                                            .isNotEmpty) ...[
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.72),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: const Border(
                                                left: BorderSide(
                                                    color: Color(0xFF14B8A6),
                                                    width: 3),
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  l10n.tr('replyingTo', {
                                                    'name': replySender?.name ??
                                                        l10n.t('member'),
                                                  }),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        color: const Color(
                                                            0xFF0F766E),
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  message.replyToText!,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                          color: const Color(
                                                              0xFF475569)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                        if (message.audio)
                                          _VoiceMessageBubble(
                                            durationSeconds:
                                                message.audioDurationSeconds ??
                                                    0,
                                            isPlaying:
                                                _playingMessageId == message.id,
                                            position:
                                                _playingMessageId == message.id
                                                    ? _playbackPosition
                                                    : Duration.zero,
                                            speed: _playbackSpeed,
                                            onPlay: () =>
                                                _playVoiceMessage(message),
                                            onSeek: (fraction) =>
                                                _seekVoiceMessage(
                                                    message, fraction),
                                            onSpeedPressed: _cyclePlaybackSpeed,
                                          )
                                        else if (message.image)
                                          _ImageMessageBubble(message: message)
                                        else
                                          Text(message.text),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              DateFormat(
                                                      'h:mm a', l10n.localeName)
                                                  .format(message.createdAt
                                                      .toLocal()),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall,
                                            ),
                                            if (message.pending) ...[
                                              const SizedBox(width: 6),
                                              const SizedBox.square(
                                                dimension: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 1.6),
                                              ),
                                            ] else if (message.failed) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.error_outline,
                                                size: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ] else if (mine &&
                                                status.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                status == 'seen'
                                                    ? Icons.done_all_rounded
                                                    : status == 'received'
                                                        ? Icons.done_all_rounded
                                                        : Icons.done_rounded,
                                                size: 14,
                                                color: status == 'seen'
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : const Color(0xFF64748B),
                                              ),
                                            ],
                                            if (message.edited) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                l10n.t('edited'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                        color: const Color(
                                                            0xFF64748B)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (message.reactions.isNotEmpty)
                                  Transform.translate(
                                    offset: const Offset(0, -8),
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 10, right: 10, bottom: 2),
                                      child: _MessageReactionsPill(
                                        reactions: message.reactions,
                                        onTap: () =>
                                            _showReactionDetails(message),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (replyingTo != null) ...[
                    _ReplyComposerPreview(
                      senderName: _senderName(replyingTo!),
                      text: replyingTo!.text,
                      onCancel: () => setState(() => replyingTo = null),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (editingMessage != null) ...[
                    _ComposerModePreview(
                      title: l10n.t('editingMessage'),
                      text: editingMessage!.text,
                      onCancel: () => setState(() {
                        editingMessage = null;
                        controller.clear();
                      }),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildComposer(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _senderName(ChatMessage message) {
    if (message.system) return 'Hoomy';
    return widget.viewModel.memberById(message.senderId)?.name ??
        context.l10n.t('member');
  }

  Widget _buildComposer(BuildContext context) {
    if (isRecording || _voicePreviewPath != null) {
      return _RecordingComposerBar(
        locked: _recordingLocked,
        willCancel: _recordingWillCancel,
        preview: _voicePreviewPath != null,
        elapsed: _recordingElapsed,
        cancelProgress: _recordingCancelProgress(context),
        lockProgress: _recordingLockProgress,
        previewDurationSeconds: _voicePreviewDurationSeconds,
        previewPlaying: _playingMessageId == 'voice-preview',
        onCancel: _cancelRecording,
        onStop: _stopRecordingForPreview,
        onSend: _sendCurrentVoice,
        onPlayPreview: _playVoicePreview,
      );
    }

    final l10n = context.l10n;
    final showSendButton = editingMessage != null || _hasMessageText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: l10n.t('messageTheFamily'),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.t('attachImage'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _sendImageFromSource(ImageSource.gallery),
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  IconButton(
                    tooltip: l10n.t('captureImage'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _sendImageFromSource(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (showSendButton)
          IconButton.filled(
            onPressed: _sendTextOrEdit,
            icon:
                Icon(editingMessage == null ? Icons.send : Icons.check_rounded),
          )
        else
          _VoiceRecordHoldButton(
            enabled: true,
            onStart: _startRecording,
            onUpdate: _updateRecordingGesture,
            onEnd: _finishHoldRecording,
          ),
      ],
    );
  }

  Duration get _recordingElapsed {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  double _recordingCancelProgress(BuildContext context) {
    return resolveVoiceRecordingGesture(
      start: Offset.zero,
      current: _recordingDragDelta,
      textDirection: Directionality.of(context),
    ).cancelProgress;
  }

  double get _recordingLockProgress {
    return resolveVoiceRecordingGesture(
      start: Offset.zero,
      current: _recordingDragDelta,
      textDirection: ui.TextDirection.ltr,
    ).lockProgress;
  }

  Future<void> _sendTextOrEdit() async {
    final l10n = context.l10n;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    final edit = editingMessage;
    final reply = replyingTo;
    final fallbackError = edit == null
        ? l10n.t('couldNotSendMessage')
        : l10n.t('couldNotEditMessage');
    controller.clear();
    setState(() {
      editingMessage = null;
      replyingTo = null;
    });
    final sent = edit == null
        ? await widget.viewModel.sendMessage(text, replyTo: reply)
        : await widget.viewModel.editMessage(edit, text);
    if (!sent && mounted) {
      setState(() {
        if (edit != null) {
          editingMessage = edit;
          controller.text = text;
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        } else if (reply != null) {
          replyingTo = reply;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.viewModel.errorMessage ?? fallbackError),
        ),
      );
    }
  }

  Future<void> _sendImageFromSource(ImageSource source) async {
    final l10n = context.l10n;
    if (editingMessage != null || isRecording || _voicePreviewPath != null) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final reply = replyingTo;
      setState(() => replyingTo = null);
      final sent = await widget.viewModel.sendImageMessage(
        imageBase64: base64Encode(bytes),
        imageMimeType: _mimeTypeForImagePath(picked.path),
        replyTo: reply,
      );
      if (!sent && mounted) {
        setState(() {
          if (reply != null) replyingTo = reply;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.viewModel.errorMessage ??
                l10n.t('couldNotSendImageMessage')),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('couldNotSendImageMessage'))),
      );
    }
  }

  String _mimeTypeForImagePath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _showMessageOptions(
    ChatMessage message,
    Offset position, {
    required bool mine,
  }) async {
    final l10n = context.l10n;
    final canEdit = mine &&
        !message.system &&
        !message.pending &&
        !message.audio &&
        !message.image;
    final canViewInfo = mine && !message.system;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    const menuWidth = 280.0;
    final top = (position.dy - 12).clamp(12.0, overlay.size.height - 260);
    final left = (position.dx - (mine ? menuWidth : 0))
        .clamp(12.0, overlay.size.width - menuWidth - 12);
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l10n.t('messageOptions'),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                color: Colors.transparent,
                child: _MessageOptionsPopup(
                  reactionEmojis: message.pending ? const [] : _reactionEmojis,
                  actions: [
                    _MessageOptionData(
                      value: 'reply',
                      title: l10n.t('reply'),
                      subtitle: mine
                          ? l10n.t('replyToYourMessage')
                          : l10n.t('replyToFamilyMessage'),
                      icon: Icons.reply_rounded,
                      iconBackground: const Color(0xFFEFFDF8),
                      iconColor: const Color(0xFF0F766E),
                    ),
                    if (canEdit)
                      _MessageOptionData(
                        value: 'edit',
                        title: l10n.t('edit'),
                        subtitle: l10n.t('editYourMessage'),
                        icon: Icons.edit_rounded,
                        iconBackground: const Color(0xFFEFFDF8),
                        iconColor: const Color(0xFF0F766E),
                      ),
                    if (canViewInfo)
                      _MessageOptionData(
                        value: 'info',
                        title: l10n.t('info'),
                        subtitle: l10n.t('viewMessageInfo'),
                        icon: Icons.info_outline_rounded,
                        iconBackground: const Color(0xFFEFF6FF),
                        iconColor: const Color(0xFF2563EB),
                      ),
                  ],
                  onSelected: (value) => Navigator.of(dialogContext).pop(value),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
    if (!mounted || selected == null) return;
    if (selected.startsWith('reaction:')) {
      final emoji = selected.substring('reaction:'.length);
      final reacted = await widget.viewModel.reactToMessage(message, emoji);
      if (!reacted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.viewModel.errorMessage ?? l10n.t('couldNotReactMessage'),
            ),
          ),
        );
      }
    } else if (selected == 'reply') {
      setState(() {
        editingMessage = null;
        replyingTo = message;
      });
    } else if (selected == 'edit') {
      setState(() {
        replyingTo = null;
        editingMessage = message;
        controller.text = message.text;
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
      });
    } else if (selected == 'info') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageInfoScreen(
            viewModel: widget.viewModel,
            initialMessage: message,
          ),
        ),
      );
    }
  }

  Future<void> _showReactionDetails(ChatMessage message) async {
    final currentMessage = widget.viewModel.messages.firstWhere(
      (item) => item.id == message.id,
      orElse: () => message,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final l10n = context.l10n;
        final reactions = currentMessage.reactions;
        final currentUserId = widget.viewModel.currentUser?.id;
        ChatMessageReaction? currentUserReaction;
        for (final reaction in reactions) {
          if (reaction.userId == currentUserId) {
            currentUserReaction = reaction;
            break;
          }
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.t('reactions'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                for (final reaction in reactions) ...[
                  _ReactionDetailTile(
                    emoji: reaction.emoji,
                    name: widget.viewModel.memberById(reaction.userId)?.name ??
                        l10n.t('member'),
                    onRemove: reaction == currentUserReaction
                        ? () async {
                            final removed =
                                await widget.viewModel.reactToMessage(
                              currentMessage,
                              reaction.emoji,
                            );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            if (!removed && mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    widget.viewModel.errorMessage ??
                                        l10n.t('couldNotReactMessage'),
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                  ),
                  if (reaction != reactions.last)
                    const Divider(height: 12, color: Color(0xFFE2E8F0)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changePlaybackSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _audioPlayer.setPlaybackRate(speed);
  }

  Future<void> _cyclePlaybackSpeed() async {
    final nextSpeed = _playbackSpeed < 1.5
        ? 1.5
        : _playbackSpeed < 2
            ? 2.0
            : 1.0;
    await _changePlaybackSpeed(nextSpeed);
  }

  Future<void> _startRecording(Offset globalPosition) async {
    final l10n = context.l10n;
    if (editingMessage != null || isRecording || _voicePreviewPath != null) {
      return;
    }
    try {
      await HapticFeedback.selectionClick();
      final permissionCheckStartedAt = DateTime.now();
      final hasPermission = await _audioRecorder.hasPermission();
      final permissionCheckDuration =
          DateTime.now().difference(permissionCheckStartedAt);
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('microphonePermissionDenied'))),
        );
        return;
      }
      if (permissionCheckDuration > const Duration(milliseconds: 650)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('microphoneReadyHoldAgain'))),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/hoomy_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      setState(() {
        _recordingStartedAt = DateTime.now();
        _recordingPath = path;
        _recordingLocked = false;
        _recordingWillCancel = false;
        _recordingDragDelta = Offset.zero;
        _recordingCancelHapticSent = false;
        _recordingLockHapticSent = false;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && isRecording) setState(() {});
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('couldNotRecordMessage'))),
      );
    }
  }

  void _updateRecordingGesture(Offset start, Offset current) {
    if (!isRecording || _recordingLocked) return;
    final gesture = resolveVoiceRecordingGesture(
      start: start,
      current: current,
      textDirection: Directionality.of(context),
    );
    final willCancel = gesture.shouldCancel;
    final willLock = gesture.shouldLock;
    if (willCancel && !_recordingCancelHapticSent) {
      _recordingCancelHapticSent = true;
      HapticFeedback.selectionClick();
    } else if (!willCancel) {
      _recordingCancelHapticSent = false;
    }
    if (willLock && !_recordingLockHapticSent) {
      _recordingLockHapticSent = true;
      HapticFeedback.mediumImpact();
    }
    setState(() {
      _recordingDragDelta = gesture.delta;
      _recordingWillCancel = willCancel;
      if (willLock) {
        _recordingLocked = true;
        _recordingWillCancel = false;
        _recordingDragDelta = Offset.zero;
      }
    });
  }

  Future<void> _finishHoldRecording() async {
    if (!isRecording || _recordingLocked) return;
    if (_recordingWillCancel) {
      await _cancelRecording();
    } else {
      await HapticFeedback.lightImpact();
      await _sendCurrentVoice();
    }
  }

  Future<void> _stopRecordingForPreview() async {
    if (!isRecording) return;
    final result = await _stopRecording();
    if (result == null) return;
    await HapticFeedback.selectionClick();
    setState(() {
      _voicePreviewPath = result.path;
      _voicePreviewDurationSeconds = result.durationSeconds;
      _recordingLocked = false;
      _recordingWillCancel = false;
      _recordingDragDelta = Offset.zero;
    });
  }

  Future<_RecordedVoice?> _stopRecording() async {
    final startedAt = _recordingStartedAt;
    final pathBeforeStop = _recordingPath;
    final stoppedPath = await _audioRecorder.stop();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final path = stoppedPath ?? pathBeforeStop;
    final duration =
        startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds;
    setState(() {
      _recordingStartedAt = null;
      _recordingPath = null;
    });
    if (path == null || duration <= 0) return null;
    return _RecordedVoice(path: path, durationSeconds: duration);
  }

  Future<void> _cancelRecording() async {
    await HapticFeedback.selectionClick();
    final recordingPath = _recordingPath;
    final previewPath = _voicePreviewPath;
    await _audioPlayer.stop();
    if (isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (_) {}
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() {
      _recordingStartedAt = null;
      _recordingPath = null;
      _recordingLocked = false;
      _recordingWillCancel = false;
      _recordingDragDelta = Offset.zero;
      _recordingCancelHapticSent = false;
      _recordingLockHapticSent = false;
      _voicePreviewPath = null;
      _voicePreviewDurationSeconds = 0;
    });
    for (final path in [recordingPath, previewPath]) {
      if (path == null) continue;
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _sendCurrentVoice() async {
    final l10n = context.l10n;
    try {
      await _audioPlayer.stop();
      final result = isRecording
          ? await _stopRecording()
          : _voicePreviewPath == null
              ? null
              : _RecordedVoice(
                  path: _voicePreviewPath!,
                  durationSeconds: _voicePreviewDurationSeconds,
                );
      if (result == null) return;

      final bytes = await File(result.path).readAsBytes();
      final reply = replyingTo;
      setState(() {
        replyingTo = null;
        _voicePreviewPath = null;
        _voicePreviewDurationSeconds = 0;
        _recordingLocked = false;
        _recordingWillCancel = false;
        _recordingDragDelta = Offset.zero;
      });
      await HapticFeedback.lightImpact();
      final sent = await widget.viewModel.sendVoiceMessage(
        audioBase64: base64Encode(bytes),
        audioMimeType: 'audio/mp4',
        durationSeconds: result.durationSeconds,
        replyTo: reply,
      );
      if (!sent && mounted) {
        setState(() {
          if (reply != null) replyingTo = reply;
          _voicePreviewPath = result.path;
          _voicePreviewDurationSeconds = result.durationSeconds;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.viewModel.errorMessage ??
                l10n.t('couldNotSendVoiceMessage')),
          ),
        );
      } else {
        try {
          await File(result.path).delete();
        } catch (_) {}
      }
    } catch (_) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      setState(() {
        _recordingStartedAt = null;
        _recordingPath = null;
        _recordingLocked = false;
        _recordingWillCancel = false;
        _recordingDragDelta = Offset.zero;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('couldNotSendVoiceMessage'))),
      );
    }
  }

  Future<void> _playVoiceMessage(ChatMessage message) async {
    final audioBase64 = message.audioBase64;
    if (audioBase64 == null || audioBase64.isEmpty) return;
    if (_playingMessageId == message.id) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }

    try {
      await _audioPlayer.stop();
      setState(() {
        _playingMessageId = message.id;
        _playbackPosition = Duration.zero;
      });
      await _audioPlayer.play(BytesSource(base64Decode(audioBase64)));
      await _audioPlayer.setPlaybackRate(_playbackSpeed);
    } catch (_) {
      if (mounted) setState(() => _playingMessageId = null);
    }
  }

  Future<void> _playVoicePreview() async {
    final path = _voicePreviewPath;
    if (path == null) return;
    const previewId = 'voice-preview';
    if (_playingMessageId == previewId) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }
    try {
      final resumePreview = _playingMessageId == null &&
          _playbackPosition > Duration.zero &&
          _playbackPosition.inSeconds < _voicePreviewDurationSeconds;
      setState(() {
        _playingMessageId = previewId;
      });
      if (resumePreview) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.stop();
        setState(() => _playbackPosition = Duration.zero);
        await _audioPlayer.play(DeviceFileSource(path));
      }
      await _audioPlayer.setPlaybackRate(_playbackSpeed);
    } catch (_) {
      if (mounted) setState(() => _playingMessageId = null);
    }
  }

  Future<void> _seekVoiceMessage(ChatMessage message, double fraction) async {
    final audioBase64 = message.audioBase64;
    final totalSeconds = message.audioDurationSeconds ?? 0;
    if (audioBase64 == null || audioBase64.isEmpty || totalSeconds <= 0) {
      return;
    }
    final position = Duration(
      milliseconds: (totalSeconds * 1000 * fraction.clamp(0, 1)).round(),
    );
    try {
      if (_playingMessageId != message.id) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = message.id);
        await _audioPlayer.play(BytesSource(base64Decode(audioBase64)));
        await _audioPlayer.setPlaybackRate(_playbackSpeed);
      }
      await _audioPlayer.seek(position);
      if (mounted) setState(() => _playbackPosition = position);
    } catch (_) {
      if (mounted) setState(() => _playingMessageId = null);
    }
  }
}

class _RecordedVoice {
  const _RecordedVoice({
    required this.path,
    required this.durationSeconds,
  });

  final String path;
  final int durationSeconds;
}

class _VoiceRecordHoldButton extends StatefulWidget {
  const _VoiceRecordHoldButton({
    required this.enabled,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final bool enabled;
  final ValueChanged<Offset> onStart;
  final void Function(Offset start, Offset current) onUpdate;
  final VoidCallback onEnd;

  @override
  State<_VoiceRecordHoldButton> createState() => _VoiceRecordHoldButtonState();
}

class _VoiceRecordHoldButtonState extends State<_VoiceRecordHoldButton> {
  Offset? _start;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Listener(
      onPointerDown: widget.enabled
          ? (event) {
              if (event.kind == PointerDeviceKind.mouse &&
                  (event.buttons & kPrimaryMouseButton) == 0) {
                return;
              }
              _start = event.position;
              widget.onStart(event.position);
            }
          : null,
      onPointerMove: widget.enabled
          ? (event) {
              final start = _start;
              if (start == null) return;
              widget.onUpdate(start, event.position);
            }
          : null,
      onPointerUp: widget.enabled
          ? (_) {
              _start = null;
              widget.onEnd();
            }
          : null,
      onPointerCancel: widget.enabled
          ? (_) {
              _start = null;
              widget.onEnd();
            }
          : null,
      child: Tooltip(
        message: l10n.t('holdToRecord'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.enabled
                ? const Color(0xFFEFFDF8)
                : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mic_rounded,
            color: widget.enabled
                ? Theme.of(context).colorScheme.primary
                : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}

class _RecordingComposerBar extends StatelessWidget {
  const _RecordingComposerBar({
    required this.locked,
    required this.willCancel,
    required this.preview,
    required this.elapsed,
    required this.cancelProgress,
    required this.lockProgress,
    required this.previewDurationSeconds,
    required this.previewPlaying,
    required this.onCancel,
    required this.onStop,
    required this.onSend,
    required this.onPlayPreview,
  });

  final bool locked;
  final bool willCancel;
  final bool preview;
  final Duration elapsed;
  final double cancelProgress;
  final double lockProgress;
  final int previewDurationSeconds;
  final bool previewPlaying;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  final VoidCallback onSend;
  final VoidCallback onPlayPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = preview
        ? Duration(
            seconds: previewDurationSeconds <= 0 ? 1 : previewDurationSeconds)
        : elapsed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: willCancel ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: willCancel ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
        ),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            if (preview)
              IconButton(
                tooltip: l10n.t('playVoicePreview'),
                onPressed: onPlayPreview,
                icon: Icon(
                  previewPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              )
            else
              const _RecordingDot(),
            const SizedBox(width: 8),
            Text(
              _formatDuration(duration),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: willCancel
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LiveRecordingWaveform(
                    active: !preview,
                    danger: willCancel,
                    intensity: preview
                        ? 0
                        : (1 - cancelProgress * 0.35).clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      preview
                          ? l10n.t('voicePreview')
                          : locked
                              ? l10n.t('recordingLocked')
                              : willCancel
                                  ? l10n.t('releaseToCancel')
                                  : l10n.t('slideLeftToCancel'),
                      key: ValueKey('$preview-$locked-$willCancel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: willCancel
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            if (!preview && !locked) ...[
              const SizedBox(width: 8),
              _ActiveRecordingMicHint(
                lockProgress: lockProgress,
                tooltip: l10n.t('slideUpToLock'),
              ),
            ],
            if (preview || locked) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: l10n.t('cancel'),
                onPressed: onCancel,
                icon:
                    const Icon(Icons.delete_rounded, color: Color(0xFFDC2626)),
              ),
              if (!preview)
                IconButton(
                  tooltip: l10n.t('stopRecording'),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_rounded),
                ),
              IconButton.filled(
                tooltip: l10n.t('sendVoiceMessage'),
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
      lowerBound: 0.62,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(
        scale: _controller,
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _ActiveRecordingMicHint extends StatelessWidget {
  const _ActiveRecordingMicHint({
    required this.lockProgress,
    required this.tooltip,
  });

  final double lockProgress;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final progress = lockProgress.clamp(0.0, 1.0);
    return Tooltip(
      message: tooltip,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutBack,
        scale: 1.0 + progress * 0.18,
        child: SizedBox(
          width: 58,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 24 + progress * 4,
                height: 24 + progress * 4,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFFFFFFF),
                    const Color(0xFFCCFBF1),
                    progress,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color.lerp(
                      const Color(0xFF99F6E4),
                      const Color(0xFF14B8A6),
                      progress,
                    )!,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: 13 + progress * 2,
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 52 + progress * 4,
                height: 52 + progress * 4,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFEFFDF8),
                    const Color(0xFF14B8A6),
                    progress,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 27 + progress * 2,
                  color: Color.lerp(
                    const Color(0xFF0F766E),
                    Colors.white,
                    progress,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRecordingWaveform extends StatelessWidget {
  const _LiveRecordingWaveform({
    required this.active,
    required this.danger,
    required this.intensity,
  });

  final bool active;
  final bool danger;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: double.infinity,
      child: CustomPaint(
        painter: _LiveRecordingWaveformPainter(
          active: active,
          color: danger
              ? const Color(0xFFEF4444)
              : Theme.of(context).colorScheme.primary,
          inactiveColor: const Color(0xFFCBD5E1),
          intensity: intensity,
        ),
      ),
    );
  }
}

class _LiveRecordingWaveformPainter extends CustomPainter {
  const _LiveRecordingWaveformPainter({
    required this.active,
    required this.color,
    required this.inactiveColor,
    required this.intensity,
  });

  final bool active;
  final Color color;
  final Color inactiveColor;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 4.0;
    final count = (size.width / (barWidth + gap)).floor();
    final centerY = size.height / 2;
    final tick = DateTime.now().millisecondsSinceEpoch ~/ 160;
    for (var i = 0; i < count; i++) {
      final phase = active ? (tick + i) % 12 : i % 12;
      final wave = 0.25 + (phase <= 6 ? phase : 12 - phase) / 6 * 0.75;
      final scaledWave = 0.22 + wave * intensity.clamp(0.25, 1.0);
      final barHeight = (size.height * scaledWave).clamp(5.0, size.height);
      final paint = Paint()
        ..color = active ? color : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      final x = i * (barWidth + gap);
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiveRecordingWaveformPainter oldDelegate) {
    return active ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.intensity != intensity;
  }
}

class _MessageOptionData {
  const _MessageOptionData({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
  });

  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
}

class _MessageOptionsPopup extends StatelessWidget {
  const _MessageOptionsPopup({
    required this.reactionEmojis,
    required this.actions,
    required this.onSelected,
  });

  final List<String> reactionEmojis;
  final List<_MessageOptionData> actions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reactionEmojis.isNotEmpty)
            _MessageReactionPicker(
              emojis: reactionEmojis,
              onSelected: (emoji) => onSelected('reaction:$emoji'),
            ),
          if (reactionEmojis.isNotEmpty && actions.isNotEmpty)
            const SizedBox(height: 8),
          for (final action in actions)
            _MessageOptionTile(action: action, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _MessageReactionPicker extends StatelessWidget {
  const _MessageReactionPicker({
    required this.emojis,
    required this.onSelected,
  });

  final List<String> emojis;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final emoji in emojis)
          InkWell(
            onTap: () => onSelected(emoji),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Text(emoji, style: const TextStyle(fontSize: 21)),
            ),
          ),
      ],
    );
  }
}

class _MessageOptionTile extends StatelessWidget {
  const _MessageOptionTile({
    required this.action,
    required this.onSelected,
  });

  final _MessageOptionData action;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onSelected(action.value),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: action.iconBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(action.icon, color: action.iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF64748B),
                      height: 1.2,
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

class _MessageReactionsPill extends StatelessWidget {
  const _MessageReactionsPill({
    required this.reactions,
    required this.onTap,
  });

  final List<ChatMessageReaction> reactions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final reaction in reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in counts.entries) ...[
              Text(entry.key, style: const TextStyle(fontSize: 14)),
              if (entry.value > 1) ...[
                const SizedBox(width: 2),
                Text(
                  entry.value.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
              if (entry.key != counts.keys.last) const SizedBox(width: 5),
            ],
            const SizedBox(width: 5),
            Text(
              reactions.length.toString(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionDetailTile extends StatelessWidget {
  const _ReactionDetailTile({
    required this.emoji,
    required this.name,
    this.onRemove,
  });

  final String emoji;
  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEFFDF8),
              shape: BoxShape.circle,
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Text(
            emoji,
            style: const TextStyle(fontSize: 22),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              tooltip: context.l10n.t('removeReaction'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _ReplyComposerPreview extends StatelessWidget {
  const _ReplyComposerPreview({
    required this.senderName,
    required this.text,
    required this.onCancel,
  });

  final String senderName;
  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFDF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.tr('replyingTo', {'name': senderName}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF0F766E),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF475569)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.t('cancelReply'),
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceMessageBubble extends StatelessWidget {
  const _VoiceMessageBubble({
    required this.durationSeconds,
    required this.isPlaying,
    required this.position,
    required this.speed,
    required this.onPlay,
    required this.onSeek,
    required this.onSpeedPressed,
  });

  final int durationSeconds;
  final bool isPlaying;
  final Duration position;
  final double speed;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;
  final VoidCallback onSpeedPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safeDuration = durationSeconds <= 0 ? 1 : durationSeconds;
    final progress =
        (position.inMilliseconds / (safeDuration * 1000)).clamp(0.0, 1.0);
    final isRtl = Directionality.of(context) == ui.TextDirection.rtl;
    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: onPlay,
            icon: Icon(
              isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoiceWaveformSeekBar(
                  progress: progress,
                  rtl: isRtl,
                  onSeek: onSeek,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.tr('voiceMessageSeconds', {'seconds': safeDuration}),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.t('playbackSpeed'),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onSpeedPressed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFFDF8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: Text(
                  '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 1)}x',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF0F766E),
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble({required this.message});

  final ChatMessage message;
  static const _mediaChannel = MethodChannel('hoomy/media');

  @override
  Widget build(BuildContext context) {
    final imageBase64 = message.imageBase64;
    if (imageBase64 == null || imageBase64.isEmpty) {
      return Text(message.text);
    }

    try {
      final bytes = base64Decode(imageBase64);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showImageViewer(context, bytes),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            bytes,
            width: 310,
            height: 240,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Text(message.text),
          ),
        ),
      );
    } catch (_) {
      return Text(message.text);
    }
  }

  void _showImageViewer(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 12,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 12,
                child: IconButton.filledTonal(
                  tooltip: context.l10n.t('saveImage'),
                  onPressed: () => _saveImage(context, bytes),
                  icon: const Icon(Icons.download_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveImage(BuildContext context, Uint8List bytes) async {
    final l10n = context.l10n;
    final extension = _imageExtension(bytes);
    final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _mediaChannel.invokeMethod<String>('saveImageToGallery', {
        'bytes': bytes,
        'fileName': 'hoomy_${DateTime.now().millisecondsSinceEpoch}.$extension',
        'mimeType': mimeType,
      });
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('imageSavedToPhone'))),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('couldNotSaveImage'))),
      );
    }
  }

  String _imageExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }
}

class _VoiceWaveformSeekBar extends StatelessWidget {
  const _VoiceWaveformSeekBar({
    required this.progress,
    required this.rtl,
    required this.onSeek,
  });

  final double progress;
  final bool rtl;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    void seekFromPosition(Offset localPosition, BoxConstraints constraints) {
      final width = constraints.maxWidth;
      if (width <= 0) return;
      final raw = (localPosition.dx / width).clamp(0.0, 1.0);
      onSeek(rtl ? 1 - raw : raw);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              seekFromPosition(details.localPosition, constraints),
          onHorizontalDragUpdate: (details) =>
              seekFromPosition(details.localPosition, constraints),
          child: SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              painter: _VoiceWaveformPainter(
                progress: progress,
                rtl: rtl,
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor: const Color(0xFFCBD5E1),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.progress,
    required this.rtl,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final bool rtl;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const gap = 3.0;
    final count = (size.width / (barWidth + gap)).floor();
    final centerY = size.height / 2;
    final activeWidth = size.width * progress;

    for (var i = 0; i < count; i++) {
      final x = i * (barWidth + gap);
      final wave = 0.35 + (((i * 37) % 11) / 10) * 0.65;
      final barHeight = (size.height * wave).clamp(6.0, size.height);
      final paint = Paint()
        ..color = rtl
            ? x >= size.width - activeWidth
                ? activeColor
                : inactiveColor
            : x <= activeWidth
                ? activeColor
                : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        activeColor != oldDelegate.activeColor ||
        inactiveColor != oldDelegate.inactiveColor;
  }
}

class _ComposerModePreview extends StatelessWidget {
  const _ComposerModePreview({
    required this.title,
    required this.text,
    required this.onCancel,
  });

  final String title;
  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF475569)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.t('cancelEdit'),
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
