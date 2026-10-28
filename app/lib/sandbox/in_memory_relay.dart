import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';

/// In-memory relay for the sandbox build and tests.
final class InMemoryRelayNetwork {
  final _clients = <String, InMemoryRelayClient>{};

  /// Every envelope that passed through, for inspection.
  final traffic = <Envelope>[];

  /// When set, lets a test alter envelopes in flight.
  Envelope Function(Envelope)? tamper;

  InMemoryRelayClient client(String id) => InMemoryRelayClient._(this, id);

  void _deliver(InMemoryRelayClient from, Envelope e) {
    traffic.add(e);
    final target = _clients[e.to];
    scheduleMicrotask(() {
      if (target == null) {
        from._undeliverable.add(UndeliverableFrame(envelopeId: e.id, to: e.to));
      } else {
        target._envelopes.add(tamper?.call(e) ?? e);
      }
    });
  }

  void _setOnline(InMemoryRelayClient c, {required bool online}) {
    if (online) {
      _clients[c.id] = c;
    } else if (_clients[c.id] == c) {
      _clients.remove(c.id);
    }
    for (final other in _clients.values) {
      if (other._watched.contains(c.id)) {
        other._presence.add(PresenceFrame(id: c.id, online: online));
      }
    }
  }
}

final class InMemoryRelayClient implements RelayClient {
  InMemoryRelayClient._(this._net, this.id);
  final InMemoryRelayNetwork _net;
  final String id;
  final Store<ConnectionStatus> _status = Store(ConnectionStatus.offline);
  final _envelopes = StreamController<Envelope>.broadcast();
  final _undeliverable = StreamController<UndeliverableFrame>.broadcast();
  final _presence = StreamController<PresenceFrame>.broadcast();
  Set<String> _watched = {};

  @override
  Stream<ConnectionStatus> get status => _status.stream;
  @override
  ConnectionStatus get currentStatus => _status.value;
  @override
  Stream<Envelope> get envelopes => _envelopes.stream;
  @override
  Stream<UndeliverableFrame> get undeliverable => _undeliverable.stream;
  @override
  Stream<PresenceFrame> get presence => _presence.stream;

  @override
  Future<void> connect(String url) async {
    _net._setOnline(this, online: true);
    _status.value = ConnectionStatus.online;
  }

  @override
  Future<void> disconnect() async {
    _net._setOnline(this, online: false);
    _status.value = ConnectionStatus.offline;
  }

  @override
  bool send(Envelope envelope) {
    if (_status.value != ConnectionStatus.online) return false;
    _net._deliver(this, envelope);
    return true;
  }

  @override
  void watch(Iterable<String> ids) {
    _watched = ids.toSet();
    for (final i in _watched) {
      _presence.add(PresenceFrame(id: i, online: _net._clients.containsKey(i)));
    }
  }
}
