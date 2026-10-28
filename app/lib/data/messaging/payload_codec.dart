import 'dart:convert';

import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';

/// JSON form of [WirePayload]. This is the plaintext that gets encrypted.
abstract final class PayloadCodec {
  static List<int> encode(WirePayload p) => utf8.encode(jsonEncode(_toJson(p)));

  /// Throws [FormatException] for anything it does not understand.
  static WirePayload decode(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      return _fromJson(json);
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      throw FormatException('Bad payload: $e');
    }
  }

  static Map<String, Object?> _toJson(WirePayload p) => switch (p) {
    ChatPayload() => {
      'k': 'chat',
      'id': p.messageId,
      'at': p.sentAt.millisecondsSinceEpoch,
      if (p.replyToId != null) 're': p.replyToId,
      if (p.groupId != null) 'g': p.groupId,
      ..._content(p.content),
    },
    ReceiptPayload() => {
      'k': 'receipt',
      'kind': p.kind.name,
      'ids': p.messageIds,
      if (p.groupId != null) 'g': p.groupId,
    },
    TypingPayload() => {'k': 'typing', if (p.groupId != null) 'g': p.groupId},
    ReactionPayload() => {
      'k': 'react',
      'id': p.messageId,
      'e': p.emoji,
      if (p.groupId != null) 'g': p.groupId,
    },
    DeletePayload() => {
      'k': 'delete',
      'id': p.messageId,
      if (p.groupId != null) 'g': p.groupId,
    },
    GroupUpdatePayload() => {'k': 'group', 'group': p.group.toJson()},
    GroupLeavePayload() => {'k': 'leave', 'g': p.groupId},
    CallPayload() => {
      'k': 'call',
      'call': p.callId,
      'a': p.action.name,
      if (p.groupId != null) 'g': p.groupId,
      if (p.sdp != null) 'sdp': p.sdp,
      if (p.candidate != null) 'c': p.candidate,
      if (p.sdpMid != null) 'mid': p.sdpMid,
      if (p.sdpMLineIndex != null) 'mli': p.sdpMLineIndex,
    },
  };

  static Map<String, Object?> _content(MessageContent c) => switch (c) {
    TextContent(:final text) => {'t': 'text', 'text': text},
    ImageContent(:final bytes) => {'t': 'image', 'data': base64Encode(bytes)},
    VoiceContent(:final bytes, :final duration) => {
      't': 'voice',
      'data': base64Encode(bytes),
      'ms': duration.inMilliseconds,
    },
  };

  static WirePayload _fromJson(Map<String, Object?> j) {
    final g = j['g'] as String?;
    return switch (j['k']) {
      'chat' => ChatPayload(
        messageId: j['id']! as String,
        sentAt: DateTime.fromMillisecondsSinceEpoch(j['at']! as int),
        replyToId: j['re'] as String?,
        groupId: g,
        content: _contentFrom(j),
      ),
      'receipt' => ReceiptPayload(
        kind: ReceiptKind.values.byName(j['kind']! as String),
        messageIds: (j['ids']! as List).cast<String>(),
        groupId: g,
      ),
      'typing' => TypingPayload(groupId: g),
      'react' => ReactionPayload(
        messageId: j['id']! as String,
        emoji: j['e']! as String,
        groupId: g,
      ),
      'delete' => DeletePayload(messageId: j['id']! as String, groupId: g),
      'group' => GroupUpdatePayload(
        Group.fromJson((j['group']! as Map).cast<String, Object?>()),
      ),
      'leave' => GroupLeavePayload(g!),
      'call' => CallPayload(
        callId: j['call']! as String,
        action: CallAction.values.byName(j['a']! as String),
        groupId: g,
        sdp: j['sdp'] as String?,
        candidate: j['c'] as String?,
        sdpMid: j['mid'] as String?,
        sdpMLineIndex: j['mli'] as int?,
      ),
      final k => throw FormatException('Unknown payload kind: $k'),
    };
  }

  static MessageContent _contentFrom(Map<String, Object?> j) =>
      switch (j['t']) {
        'text' => TextContent(j['text']! as String),
        'image' => ImageContent(base64Decode(j['data']! as String)),
        'voice' => VoiceContent(
          base64Decode(j['data']! as String),
          Duration(milliseconds: j['ms']! as int),
        ),
        final t => throw FormatException('Unknown content type: $t'),
      };
}
