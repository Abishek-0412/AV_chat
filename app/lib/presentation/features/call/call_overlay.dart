import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/services/call_service.dart';
import 'package:av_chat/presentation/shared/format.dart';
import 'package:av_chat/presentation/shared/names.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen call UI drawn above everything while a call exists.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callProvider).value;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      ),
      child: call == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : _CallView(key: ValueKey(call.callId), call: call),
    );
  }
}

class _CallView extends ConsumerStatefulWidget {
  const _CallView({required this.call, super.key});
  final CallState call;

  @override
  ConsumerState<_CallView> createState() => _CallViewState();
}

class _CallViewState extends ConsumerState<_CallView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.call.phase == CallPhase.incoming) {
        unawaited(HapticFeedback.vibrate());
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final calls = ref.watch(sessionProvider).value?.calls;
    final title = titleOf(ref, call.conversation);
    final ringing =
        call.phase == CallPhase.calling || call.phase == CallPhase.incoming;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B5F57), Color(0xFF062F35)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'End-to-end encrypted',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
                const Spacer(),
                _Pulse(
                  active: ringing,
                  child: AvAvatar(
                    seed: call.conversation.key,
                    name: title,
                    radius: 56,
                    icon: call.isGroup ? Icons.groups_2_outlined : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.sm),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _status(call),
                    key: ValueKey(_status(call)),
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                ),
                if (call.isGroup && call.phase != CallPhase.incoming) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _Participants(call: call),
                ],
                const Spacer(),
                if (calls != null) _controls(call, calls, scheme),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _status(CallState c) => switch (c.phase) {
    CallPhase.calling =>
      c.isGroup ? 'Calling the group…' : (c.ringing ? 'Ringing…' : 'Calling…'),
    CallPhase.incoming =>
      c.isGroup
          ? '${nameOf(ref, c.inviter)} is calling the group'
          : 'Incoming voice call',
    CallPhase.connecting => 'Connecting…',
    CallPhase.active =>
      c.activeSince == null
          ? 'Connected'
          : Format.duration(DateTime.now().difference(c.activeSince!)),
    CallPhase.ended => switch (c.endReason) {
      CallEndReason.declined => 'Declined',
      CallEndReason.busy => 'Busy on another call',
      CallEndReason.unavailable => 'Not available',
      CallEndReason.noAnswer => 'No answer',
      CallEndReason.failed => 'Connection lost',
      _ => 'Call ended',
    },
  };

  Widget _controls(CallState call, CallService calls, ColorScheme scheme) {
    if (call.phase == CallPhase.ended) return const SizedBox(height: 88);
    if (call.phase == CallPhase.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            label: 'Decline',
            icon: Icons.call_end,
            color: const Color(0xFFDC2626),
            onTap: calls.decline,
          ),
          _RoundButton(
                label: 'Accept',
                icon: Icons.call,
                color: const Color(0xFF16A34A),
                onTap: calls.accept,
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(end: 1.08, duration: 700.ms),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          label: call.muted ? 'Unmute' : 'Mute',
          icon: call.muted ? Icons.mic_off : Icons.mic_none,
          color: call.muted ? Colors.white : Colors.white24,
          iconColor: call.muted ? const Color(0xFF062F35) : Colors.white,
          onTap: calls.toggleMute,
        ),
        _RoundButton(
          label: 'End',
          icon: Icons.call_end,
          color: const Color(0xFFDC2626),
          onTap: calls.hangUp,
        ),
        _RoundButton(
          label: 'Speaker',
          icon: call.speaker ? Icons.volume_up : Icons.volume_down_outlined,
          color: call.speaker ? Colors.white : Colors.white24,
          iconColor: call.speaker ? const Color(0xFF062F35) : Colors.white,
          onTap: calls.toggleSpeaker,
        ),
      ],
    );
  }
}

class _Participants extends ConsumerWidget {
  const _Participants({required this.call});
  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = <AvId>{...call.joined, ...call.connected};
    if (ids.isEmpty) {
      return const Text(
        'Waiting for others to join…',
        style: TextStyle(color: Colors.white60),
      );
    }
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.lg,
      alignment: WrapAlignment.center,
      children: [
        for (final id in ids)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: call.connected.contains(id) ? 1 : 0.45,
                child: AvAvatar(
                  seed: DirectRef(id).key,
                  name: nameOf(ref, id),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                nameOf(ref, id),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ).animate().fadeIn().scale(begin: const Offset(0.8, 0.8)),
      ],
    );
  }
}

class _Pulse extends StatelessWidget {
  const _Pulse({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            for (final delay in [0, 600])
              Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white24,
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(), delay: delay.ms)
                  .scaleXY(begin: 1, end: 1.6, duration: 1400.ms)
                  .fadeOut(duration: 1400.ms),
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Padding(padding: const EdgeInsets.all(4), child: child),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconColor = Colors.white,
  });
  final String label;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                unawaited(HapticFeedback.lightImpact());
                unawaited(Future.sync(onTap));
              },
              child: SizedBox.square(
                dimension: 68,
                child: Icon(icon, color: iconColor, size: 30),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
