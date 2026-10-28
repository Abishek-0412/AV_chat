import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';

/// Who is online right now, for the people we care about.
final class PresenceService {
  PresenceService(this._relay);

  final RelayClient _relay;
  final online = Store<Set<AvId>>(const {});
  final _subs = <StreamSubscription<Object?>>[];

  void init() {
    _subs
      ..add(
        _relay.presence.listen((p) {
          final id = AvId.tryParse(p.id);
          if (id == null) return;
          online.value = p.online
              ? {...online.value, id}
              : ({...online.value}..remove(id));
        }),
      )
      ..add(
        _relay.status.listen((s) {
          if (s != ConnectionStatus.online) online.value = const {};
        }),
      );
  }

  bool isOnline(AvId id) => online.value.contains(id);

  void follow(Iterable<AvId> ids) =>
      _relay.watch({for (final id in ids) id.value});

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
