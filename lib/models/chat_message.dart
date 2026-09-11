class ChatMessageReaction {
  final String userId;
  final String emoji;
  final DateTime? reactedAt;

  const ChatMessageReaction({
    required this.userId,
    required this.emoji,
    this.reactedAt,
  });
}

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool system;
  final bool pending;
  final bool failed;
  final List<String> receivedBy;
  final List<String> seenBy;
  final String? replyToMessageId;
  final String? replyToSenderId;
  final String? replyToText;
  final bool edited;
  final DateTime? editedAt;
  final bool audio;
  final String? audioBase64;
  final String? audioMimeType;
  final int? audioDurationSeconds;
  final bool image;
  final String? imageBase64;
  final String? imageMimeType;
  final List<ChatMessageReaction> reactions;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.system = false,
    this.pending = false,
    this.failed = false,
    this.receivedBy = const [],
    this.seenBy = const [],
    this.replyToMessageId,
    this.replyToSenderId,
    this.replyToText,
    this.edited = false,
    this.editedAt,
    this.audio = false,
    this.audioBase64,
    this.audioMimeType,
    this.audioDurationSeconds,
    this.image = false,
    this.imageBase64,
    this.imageMimeType,
    this.reactions = const [],
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? text,
    DateTime? createdAt,
    bool? system,
    bool? pending,
    bool? failed,
    List<String>? receivedBy,
    List<String>? seenBy,
    String? replyToMessageId,
    String? replyToSenderId,
    String? replyToText,
    bool? edited,
    DateTime? editedAt,
    bool? audio,
    String? audioBase64,
    String? audioMimeType,
    int? audioDurationSeconds,
    bool? image,
    String? imageBase64,
    String? imageMimeType,
    List<ChatMessageReaction>? reactions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      system: system ?? this.system,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      receivedBy: receivedBy ?? this.receivedBy,
      seenBy: seenBy ?? this.seenBy,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToText: replyToText ?? this.replyToText,
      edited: edited ?? this.edited,
      editedAt: editedAt ?? this.editedAt,
      audio: audio ?? this.audio,
      audioBase64: audioBase64 ?? this.audioBase64,
      audioMimeType: audioMimeType ?? this.audioMimeType,
      audioDurationSeconds: audioDurationSeconds ?? this.audioDurationSeconds,
      image: image ?? this.image,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageMimeType: imageMimeType ?? this.imageMimeType,
      reactions: reactions ?? this.reactions,
    );
  }

  String deliveryStatusFor(String? currentUserId) {
    if (failed) return 'failed';
    if (pending) return 'pending';
    if (currentUserId == null || senderId != currentUserId) return '';
    if (seenBy.any((id) => id != currentUserId)) return 'seen';
    if (receivedBy.any((id) => id != currentUserId)) return 'received';
    return 'sent';
  }
}
