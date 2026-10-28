import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/sandbox/sandbox_bot.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds the demo bots as contacts (and a demo group) once the user has
/// finished onboarding in the sandbox build.
class SandboxSeeder extends ConsumerStatefulWidget {
  const SandboxSeeder({
    required this.bots,
    required this.groupWith,
    required this.child,
    super.key,
  });

  final List<SandboxBot> bots;

  /// Bots that share a demo group with the user.
  final List<SandboxBot> groupWith;
  final Widget child;

  @override
  ConsumerState<SandboxSeeder> createState() => _SandboxSeederState();
}

class _SandboxSeederState extends ConsumerState<SandboxSeeder> {
  var _seeded = false;

  Future<void> _seed() async {
    final session = ref.read(sessionProvider).value;
    if (session == null || _seeded) return;
    _seeded = true;
    for (final bot in widget.bots) {
      if (session.contacts.byId(bot.identity.id) == null) {
        await session.contacts.addFromCard(bot.card);
      }
    }
    if (session.groups.groups.value.isEmpty && widget.groupWith.isNotEmpty) {
      // Let the bot handshakes finish first.
      await Future<void>.delayed(const Duration(seconds: 1));
      await session.groups.create('Weekend plan', [
        for (final b in widget.groupWith) b.asPeer,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, next) {
      if (next.value != null) unawaited(_seed());
    });
    return widget.child;
  }
}
