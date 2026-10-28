import 'dart:typed_data';

import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/value_objects/message_status.dart';
import 'package:av_protocol/av_protocol.dart';

sealed class MessageContent {
  const MessageContent();
}

final class TextContent extends MessageContent {
  const TextContent(this.text);
  final String text;
}

final class ImageContent extends MessageContent {
  const ImageContent(this.bytes);
  final Uint8List bytes;
}

final class VoiceContent extends MessageContent {
  const VoiceContent(this.bytes, this.duration);
  final Uint8List bytes;
  final Duration duration;
}

/// A chat message. Exists in memory only.
final class Message {
  const Message({
    required this.id,
    required this.conversation,
    required this.sender,
    required this.outgoing,
    required this.content,
    required this.sentAt,
    required this.status,
    this.replyToId,
    this.reactions = const {},
    this.deleted = false,
  });

  final String id;
  final ConversationRef conversation;
  final AvId sender;
  final bool outgoing;
  final MessageContent content;
  final DateTime sentAt;
  final MessageStatus status;
  final String? replyToId;

  /// Emoji per person who reacted.
  final Map<AvId, String> reactions;

  /// "Deleted for everyone": content is gone, a placeholder remains.
  final bool deleted;

  Message copyWith({
    MessageStatus? status,
    Map<AvId, String>? reactions,
    bool? deleted,
  }) => Message(
    id: id,
    conversation: conversation,
    sender: sender,
    outgoing: outgoing,
    content: deleted ?? false ? const TextContent('') : content,
    sentAt: sentAt,
    status: status ?? this.status,
    replyToId: replyToId,
    reactions: reactions ?? this.reactions,
    deleted: deleted ?? this.deleted,
  );
}
