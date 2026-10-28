import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/message.dart';

/// Everything that travels inside an encrypted envelope. The relay sees
/// only ciphertext, so it cannot tell a message from a typing signal.
sealed class WirePayload {
  const WirePayload();
}

/// Payloads that belong to a 1:1 chat (groupId null) or a group chat.
sealed class ConversationPayload extends WirePayload {
  const ConversationPayload({this.groupId});
  final String? groupId;
}

final class ChatPayload extends ConversationPayload {
  const ChatPayload({
    required this.messageId,
    required this.content,
    required this.sentAt,
    this.replyToId,
    super.groupId,
  });
  final String messageId;
  final MessageContent content;
  final DateTime sentAt;
  final String? replyToId;
}

enum ReceiptKind { delivered, read }

final class ReceiptPayload extends ConversationPayload {
  const ReceiptPayload({
    required this.kind,
    required this.messageIds,
    super.groupId,
  });
  final ReceiptKind kind;
  final List<String> messageIds;
}

final class TypingPayload extends ConversationPayload {
  const TypingPayload({super.groupId});
}

final class ReactionPayload extends ConversationPayload {
  const ReactionPayload({
    required this.messageId,
    required this.emoji,
    super.groupId,
  });
  final String messageId;

  /// Empty string removes the reaction.
  final String emoji;
}

final class DeletePayload extends ConversationPayload {
  const DeletePayload({required this.messageId, super.groupId});
  final String messageId;
}

/// Sent by the group owner to every member whenever the group changes.
final class GroupUpdatePayload extends WirePayload {
  const GroupUpdatePayload(this.group);
  final Group group;
}

final class GroupLeavePayload extends WirePayload {
  const GroupLeavePayload(this.groupId);
  final String groupId;
}

enum CallAction {
  invite,
  ringing,
  accept,
  decline,
  busy,
  offer,
  answer,
  ice,
  hangup,
}

/// WebRTC signaling, end-to-end encrypted like everything else.
final class CallPayload extends WirePayload {
  const CallPayload({
    required this.callId,
    required this.action,
    this.groupId,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });
  final String callId;
  final CallAction action;
  final String? groupId;
  final String? sdp;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}
