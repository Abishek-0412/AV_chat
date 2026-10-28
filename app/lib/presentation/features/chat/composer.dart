import 'dart:async';

import 'package:av_chat/data/platform/media_capture.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/presentation/features/chat/message_bubble.dart';
import 'package:av_chat/presentation/shared/format.dart';
import 'package:av_chat/presentation/shared/theme/app_motion.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Text box, photo button and hold-free voice recorder.
class Composer extends StatefulWidget {
  const Composer({
    required this.media,
    required this.onSend,
    required this.onTyping,
    required this.onContent,
    this.enabled = true,
    this.disabledHint,
    this.replyTo,
    this.replyToName,
    this.onCancelReply,
    super.key,
  });

  final MediaCapture media;
  final bool enabled;
  final String? disabledHint;
  final Message? replyTo;
  final String? replyToName;
  final VoidCallback? onCancelReply;
  final ValueChanged<String> onSend;
  final VoidCallback onTyping;
  final ValueChanged<MessageContent> onContent;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _recording = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  bool get _hasText => _text.text.trim().isNotEmpty;

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != null && old.replyTo?.id != widget.replyTo?.id) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_recording) unawaited(widget.media.cancelRecording());
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    if (!_hasText) return;
    widget.onSend(_text.text);
    _text.clear();
    setState(() {});
  }

  Future<void> _pickImage() async {
    final fromCamera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (fromCamera == null) return;
    final bytes = await widget.media.pickImage(fromCamera: fromCamera);
    if (bytes != null) {
      widget.onContent(ImageContent(bytes));
    } else if (mounted) {
      _toast('No photo sent');
    }
  }

  Future<void> _startRecording() async {
    final ok = await widget.media.startRecording();
    if (!ok) {
      _toast('Microphone permission is needed for voice notes');
      return;
    }
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= MediaCapture.maxVoice) {
        unawaited(_stopRecording(send: true));
      }
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    _timer?.cancel();
    setState(() => _recording = false);
    if (!send) {
      await widget.media.cancelRecording();
      return;
    }
    final result = await widget.media.stopRecording();
    if (result == null) {
      _toast('Voice note too short');
      return;
    }
    widget.onContent(VoiceContent(result.$1, result.$2));
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (!widget.enabled) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  widget.disabledHint ?? '',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: AppMotion.medium),
      );
    }
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            child: widget.replyTo == null
                ? const SizedBox(width: double.infinity)
                : _ReplyBar(
                    message: widget.replyTo!,
                    name: widget.replyToName ?? '',
                    onCancel: widget.onCancelReply,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: _recording ? _recorderRow(scheme) : _inputRow(scheme),
          ),
        ],
      ),
    );
  }

  Widget _inputRow(ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          onPressed: _pickImage,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          tooltip: 'Send photo',
        ),
        Expanded(
          child: TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 1,
            maxLines: 5,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            // Keep the keyboard from learning or suggesting message text.
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            contextMenuBuilder: (context, state) =>
                AdaptiveTextSelectionToolbar.editableText(
                  editableTextState: state,
                ),
            decoration: const InputDecoration(
              hintText: 'Message',
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            onChanged: (_) {
              widget.onTyping();
              setState(() {});
            },
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        AnimatedSwitcher(
          duration: AppMotion.fast,
          transitionBuilder: (child, a) =>
              ScaleTransition(scale: a, child: child),
          child: _hasText
              ? IconButton.filled(
                  key: const ValueKey('send'),
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'Send',
                )
              : IconButton.filledTonal(
                  key: const ValueKey('mic'),
                  onPressed: _startRecording,
                  icon: const Icon(Icons.mic_none_rounded),
                  tooltip: 'Record voice note',
                ),
        ),
      ],
    );
  }

  Widget _recorderRow(ColorScheme scheme) {
    return Row(
      children: [
        IconButton(
          onPressed: () => _stopRecording(send: false),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Discard',
        ),
        Icon(Icons.fiber_manual_record, color: scheme.error, size: 14)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(begin: 1, end: 0.2, duration: 600.ms),
        const SizedBox(width: AppSpacing.sm),
        Text(
          Format.duration(_elapsed),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const Spacer(),
        Text(
          'Recording…',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.md),
        IconButton.filled(
          onPressed: () => _stopRecording(send: true),
          icon: const Icon(Icons.send_rounded),
          tooltip: 'Send voice note',
        ),
      ],
    ).animate().fadeIn(duration: AppMotion.fast);
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.name, this.onCancel});
  final Message message;
  final String name;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: scheme.primary, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $name',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  previewOf(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }
}
