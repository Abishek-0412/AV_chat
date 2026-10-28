import 'dart:async';

import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/presentation/features/chat/voice_note_player.dart';
import 'package:av_chat/presentation/shared/format.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/status_ticks.dart';
import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.message,
    required this.onLongPress,
    this.senderName,
    this.replyTo,
    this.replyToName,
    this.joinsPrevious = false,
    super.key,
  });

  final Message message;

  /// Shown above incoming group messages.
  final String? senderName;
  final Message? replyTo;
  final String? replyToName;

  /// Consecutive messages from the same sender sit closer together.
  final bool joinsPrevious;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final out = message.outgoing;
    final bg = out ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = out ? scheme.onPrimary : scheme.onSurface;
    final meta = fg.withValues(alpha: 0.7);
    const r = Radius.circular(18);
    const tight = Radius.circular(6);

    final body = message.deleted
        ? Text(
            'Message deleted',
            style: TextStyle(color: meta, fontStyle: FontStyle.italic),
          )
        : switch (message.content) {
            TextContent(:final text) => Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(color: fg),
            ),
            ImageContent(:final bytes) => GestureDetector(
              onTap: () => _openImage(context, message),
              child: Hero(
                tag: 'img-${message.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      semanticLabel: 'Photo',
                    ),
                  ),
                ),
              ),
            ),
            VoiceContent(:final bytes, :final duration) => VoiceNotePlayer(
              bytes: bytes,
              duration: duration,
              color: fg,
            ),
          };

    return Padding(
      padding: EdgeInsets.only(
        top: joinsPrevious ? 2 : AppSpacing.sm,
        left: out ? 56 : AppSpacing.md,
        right: out ? AppSpacing.md : 56,
      ),
      child: Align(
        alignment: out ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: out
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: message.deleted ? null : onLongPress,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: !out && joinsPrevious ? tight : r,
                    topRight: out && joinsPrevious ? tight : r,
                    bottomLeft: out ? r : tight,
                    bottomRight: out ? tight : r,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (senderName != null && !joinsPrevious)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          senderName!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (replyTo != null)
                      _ReplyQuote(
                        message: replyTo!,
                        name: replyToName ?? '',
                        color: fg,
                      ),
                    body,
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Format.time(message.sentAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: meta,
                          ),
                        ),
                        if (out) ...[
                          const SizedBox(width: 4),
                          StatusTicks(
                            message.status,
                            color: meta,
                            onPrimary: true,
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
                offset: const Offset(0, -6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Text(
                    _reactionSummary(message.reactions.values),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _reactionSummary(Iterable<String> emojis) {
    final counts = <String, int>{};
    for (final e in emojis) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key}${e.value}' : e.key)
        .join(' ');
  }

  static void _openImage(BuildContext context, Message m) {
    final bytes = (m.content as ImageContent).bytes;
    unawaited(
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (context, _, _) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Hero(
                tag: 'img-${m.id}',
                child: InteractiveViewer(child: Image.memory(bytes)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({
    required this.message,
    required this.name,
    required this.color,
  });
  final Message message;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            previewOf(message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

String previewOf(Message m) {
  if (m.deleted) return 'Message deleted';
  return switch (m.content) {
    TextContent(:final text) => text,
    ImageContent() => '📷 Photo',
    VoiceContent() => '🎤 Voice note',
  };
}
