import 'dart:async';

import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/services/call_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connects app state to what Android shows outside the app: the
/// keep-alive service and content-free "new message" / "incoming call"
/// notifications while the app is hidden.
class BackgroundCoordinator extends ConsumerStatefulWidget {
  const BackgroundCoordinator({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<BackgroundCoordinator> createState() =>
      _BackgroundCoordinatorState();
}

class _BackgroundCoordinatorState extends ConsumerState<BackgroundCoordinator>
    with WidgetsBindingObserver {
  StreamSubscription<Object?>? _arrivals;
  var _visible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_arrivals?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) unawaited(ref.read(systemAlertsProvider).clear());
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(systemAlertsProvider);
    ref
      ..listen(sessionProvider, (_, next) {
        final session = next.value;
        unawaited(_arrivals?.cancel());
        _arrivals = null;
        if (session == null) return;
        unawaited(alerts.startKeepAlive());
        _arrivals = session.chats.arrivals.listen((_) {
          if (!_visible) unawaited(alerts.newMessage());
        });
      })
      ..listen(callProvider, (prev, next) {
        final call = next.value;
        final phase = call?.phase;
        if (phase == CallPhase.incoming &&
            prev?.value?.phase != CallPhase.incoming &&
            !_visible) {
          unawaited(alerts.incomingCall());
        }
        final inCall =
            phase == CallPhase.calling ||
            phase == CallPhase.connecting ||
            phase == CallPhase.active;
        unawaited(alerts.setInCall(inCall: inCall));
      });
    return widget.child;
  }
}
