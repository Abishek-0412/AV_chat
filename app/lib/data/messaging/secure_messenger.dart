import 'dart:async';
import 'dart:convert';

import 'package:av_chat/data/messaging/payload_codec.dart';
import 'package:av_chat/data/messaging/session_crypto.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

typedef Signer = Future<List<int>> Function(List<int> data);

/// [Messenger] over the relay.
///
/// Handshake (per peer, per app run):
///   A → B  {pub, name, eph_A, peerEph: null,  sig}
///   B → A  {pub, name, eph_B, peerEph: eph_A, sig}
/// A peer answers a handshake whenever it does not echo their current
/// ephemeral key, so both sides converge after one round trip, also if
/// both start at once or one side restarts. Payloads wait in a queue
/// until the session is ready.
final class SecureMessenger implements Messenger {
  SecureMessenger({
    required RelayClient relay,
    required Identity self,
    required Signer sign,
    required SessionCrypto crypto,
    required String Function() newId,
    this.handshakeTimeout = const Duration(seconds: 20),
  }) : _relay = relay,
       _self = self,
       _sign = sign,
       _crypto = crypto,
       _newId = newId,
       _name = self.name;

  final RelayClient _relay;
  final Identity _self;
  final Signer _sign;
  final SessionCrypto _crypto;
  final String Function() _newId;
  final Duration handshakeTimeout;
  String _name;
  PeerLookup _lookup = (_) => null;

  final _sessions = <AvId, SessionKeys>{};
  final _ready = <AvId>{};
  final _queues = <AvId, List<WirePayload>>{};
  final _queueTimers = <AvId, Timer>{};
  final _strangers = <AvId, _Handshake>{};
  final _handshakeEnvelopes = <String, AvId>{};
  final _sentPayloads = _Lru<String, (AvId, WirePayload)>(2000);
  final _seen = _Lru<String, bool>(5000);
  final _subs = <StreamSubscription<Object?>>[];
  Future<void> _serial = Future.value();

  final _incoming = StreamController<Incoming>.broadcast();
  final _failures = StreamController<DeliveryFailure>.broadcast();
  final _requests = StreamController<ContactRequest>.broadcast();
  final _keysLearned = StreamController<KeyLearned>.broadcast();
  final _resets = StreamController<AvId>.broadcast();

  @override
  Stream<Incoming> get incoming => _incoming.stream;
  @override
  Stream<DeliveryFailure> get failures => _failures.stream;
  @override
  Stream<ContactRequest> get requests => _requests.stream;
  @override
  Stream<KeyLearned> get keysLearned => _keysLearned.stream;
  @override
  Stream<AvId> get sessionResets => _resets.stream;

  void start() {
    _subs
      ..add(_relay.envelopes.listen((e) => _run(() => _onEnvelope(e))))
      ..add(
        _relay.undeliverable.listen(
          (u) => _run(() async => _onUndeliverable(u)),
        ),
      )
      ..add(
        _relay.status.listen((s) {
          if (s == ConnectionStatus.online) {
            for (final peer in _queues.keys.toList()) {
              _run(() => _sendHandshake(peer));
            }
          }
        }),
      );
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    for (final t in _queueTimers.values) {
      t.cancel();
    }
    await Future.wait([
      _incoming.close(),
      _failures.close(),
      _requests.close(),
      _keysLearned.close(),
      _resets.close(),
    ]);
  }

  @override
  void setPeerLookup(PeerLookup lookup) => _lookup = lookup;

  @override
  void setDisplayName(String name) => _name = name;

  @override
  void send(AvId to, WirePayload payload) => _run(() async {
    if (_ready.contains(to)) {
      await _sendEncrypted(to, payload);
      return;
    }
    final queue = (_queues[to] ??= [])..add(payload);
    if (queue.length == 1) await _sendHandshake(to);
  });

  @override
  void introduce(AvId to) => _run(() async {
    if (!_ready.contains(to)) await _sendHandshake(to);
  });

  @override
  void accept(AvId id) => _run(() async {
    final hs = _strangers.remove(id);
    if (hs != null) await _establish(id, hs);
  });

  @override
  void forget(AvId id) => _run(() async {
    _sessions.remove(id);
    _ready.remove(id);
    _strangers.remove(id);
    _queues.remove(id);
    _queueTimers.remove(id)?.cancel();
  });

  /// All work runs one step at a time, in arrival order, so a handshake
  /// is always processed before the messages that follow it.
  void _run(Future<void> Function() step) {
    _serial = _serial.then((_) => step()).catchError((Object e, StackTrace s) {
      debugPrint('[messenger] $e');
    });
  }

  // ── Outgoing ──────────────────────────────────────────────────────

  Future<void> _sendHandshake(AvId to) async {
    final peerEph = _sessions[to]?.peerEphemeral;
    final transcript = SessionCrypto.handshakeTranscript(
      from: _self.id.value,
      to: to.value,
      ephemeral: _crypto.ephemeralPublic,
      peerEphemeral: peerEph,
    );
    final body = _Handshake(
      publicKey: _self.publicKey,
      name: _name,
      ephemeral: _crypto.ephemeralPublic,
      peerEphemeral: peerEph,
      signature: await _sign(transcript),
    );
    final envelope = Envelope(
      id: _newId(),
      from: _self.id.value,
      to: to.value,
      type: EnvelopeType.handshake,
      body: body.encode(),
    );
    _handshakeEnvelopes[envelope.id] = to;
    _relay.send(envelope);
    if (_queues[to]?.isNotEmpty ?? false) _armQueueTimeout(to);
  }

  Future<void> _sendEncrypted(AvId to, WirePayload payload) async {
    final keys = _sessions[to]!;
    final id = _newId();
    final draft = Envelope(
      id: id,
      from: _self.id.value,
      to: to.value,
      type: EnvelopeType.msg,
      body: '',
    );
    final sealed = await SessionCrypto.encrypt(
      PayloadCodec.encode(payload),
      keys.sendKey,
      SessionCrypto.aadFor(draft),
    );
    _sentPayloads[id] = (to, payload);
    final ok = _relay.send(
      Envelope(
        id: id,
        from: draft.from,
        to: draft.to,
        type: draft.type,
        body: base64Encode(sealed),
      ),
    );
    if (!ok) _failures.add(DeliveryFailure(to, payload));
  }

  void _armQueueTimeout(AvId to) {
    _queueTimers[to]?.cancel();
    _queueTimers[to] = Timer(handshakeTimeout, () {
      _run(() async => _failQueue(to));
    });
  }

  void _failQueue(AvId to) {
    _queueTimers.remove(to)?.cancel();
    final queue = _queues.remove(to) ?? const [];
    for (final p in queue) {
      _failures.add(DeliveryFailure(to, p));
    }
  }

  Future<void> _flush(AvId to) async {
    _queueTimers.remove(to)?.cancel();
    final queue = _queues.remove(to) ?? const [];
    for (final p in queue) {
      await _sendEncrypted(to, p);
    }
  }

  // ── Incoming ──────────────────────────────────────────────────────

  Future<void> _onEnvelope(Envelope e) async {
    if (e.to != _self.id.value || _seen.containsKey(e.id)) return;
    _seen[e.id] = true;
    final from = AvId.tryParse(e.from);
    if (from == null) return;
    switch (e.type) {
      case EnvelopeType.handshake:
        await _onHandshake(from, e);
      case EnvelopeType.msg:
        await _onMessage(from, e);
    }
  }

  Future<void> _onHandshake(AvId from, Envelope e) async {
    final hs = _Handshake.tryDecode(e.body);
    if (hs == null) return;
    if (AvId.fromPublicKey(hs.publicKey) != from) return;
    final valid = await SessionCrypto.verify(
      message: SessionCrypto.handshakeTranscript(
        from: from.value,
        to: _self.id.value,
        ephemeral: hs.ephemeral,
        peerEphemeral: hs.peerEphemeral,
      ),
      signature: hs.signature,
      publicKey: hs.publicKey,
    );
    if (!valid) return;

    final peer = _lookup(from);
    if (peer == null) {
      // Stranger: wait for the user to accept.
      _strangers[from] = hs;
      _requests.add(
        ContactRequest(id: from, name: hs.name, publicKey: hs.publicKey),
      );
      return;
    }
    final known = peer.publicKey;
    if (known != null &&
        !const ListEquality<int>().equals(known, hs.publicKey)) {
      debugPrint('[messenger] key mismatch for $from, ignoring');
      return;
    }
    if (known == null) {
      _keysLearned.add(KeyLearned(from, hs.name, hs.publicKey));
    }
    await _establish(from, hs);
  }

  Future<void> _establish(AvId peer, _Handshake hs) async {
    final current = _sessions[peer];
    final sameKey =
        current != null &&
        const ListEquality<int>().equals(current.peerEphemeral, hs.ephemeral);
    if (!sameKey) {
      if (current != null) _resets.add(peer);
      _sessions[peer] = await _crypto.derive(
        self: _self.id,
        peer: peer,
        peerEphemeral: hs.ephemeral,
      );
    }
    final theyKnowUs = const ListEquality<int>().equals(
      hs.peerEphemeral,
      _crypto.ephemeralPublic,
    );
    // Our reply carries their key and goes out before anything we encrypt,
    // so they can decrypt whatever follows it.
    if (!theyKnowUs) await _sendHandshake(peer);
    _ready.add(peer);
    await _flush(peer);
  }

  Future<void> _onMessage(AvId from, Envelope e) async {
    final keys = _sessions[from];
    if (keys == null || _lookup(from) == null) {
      // We restarted and lost the session: ask them to redo the handshake.
      if (_lookup(from) != null) await _sendHandshake(from);
      return;
    }
    final List<int> plain;
    try {
      plain = await SessionCrypto.decrypt(
        base64Decode(e.body),
        keys.receiveKey,
        SessionCrypto.aadFor(
          Envelope(id: e.id, from: e.from, to: e.to, type: e.type, body: ''),
        ),
      );
    } on Object {
      // They still hold keys for an earlier run of ours: our handshake
      // carries the current key and lets them catch up.
      await _sendHandshake(from);
      return;
    }
    final WirePayload payload;
    try {
      payload = PayloadCodec.decode(plain);
    } on FormatException {
      return;
    }
    _incoming.add(Incoming(from, payload));
  }

  void _onUndeliverable(UndeliverableFrame u) {
    final to = AvId.tryParse(u.to);
    if (to == null) return;
    if (_handshakeEnvelopes.remove(u.envelopeId) != null) {
      _failQueue(to);
      return;
    }
    final sent = _sentPayloads.remove(u.envelopeId);
    if (sent != null) _failures.add(DeliveryFailure(sent.$1, sent.$2));
  }
}

/// Handshake body (signed, not secret).
final class _Handshake {
  const _Handshake({
    required this.publicKey,
    required this.name,
    required this.ephemeral,
    required this.peerEphemeral,
    required this.signature,
  });

  final List<int> publicKey;
  final String name;
  final List<int> ephemeral;
  final List<int>? peerEphemeral;
  final List<int> signature;

  String encode() => base64Encode(
    utf8.encode(
      jsonEncode({
        'pub': base64Encode(publicKey),
        'name': name,
        'eph': base64Encode(ephemeral),
        if (peerEphemeral != null) 'peer': base64Encode(peerEphemeral!),
        'sig': base64Encode(signature),
      }),
    ),
  );

  static _Handshake? tryDecode(String body) {
    try {
      final j =
          jsonDecode(utf8.decode(base64Decode(body))) as Map<String, Object?>;
      final name = (j['name']! as String).trim();
      return _Handshake(
        publicKey: base64Decode(j['pub']! as String),
        name: name.isEmpty
            ? 'Unknown'
            : name.substring(0, name.length.clamp(0, 40)),
        ephemeral: base64Decode(j['eph']! as String),
        peerEphemeral: j['peer'] == null
            ? null
            : base64Decode(j['peer']! as String),
        signature: base64Decode(j['sig']! as String),
      );
    } on Object {
      return null;
    }
  }
}

/// Bounded map that forgets the oldest entries.
final class _Lru<K, V> {
  _Lru(this.capacity);
  final int capacity;
  final _map = <K, V>{}; // insertion-ordered

  bool containsKey(K key) => _map.containsKey(key);
  V? remove(K key) => _map.remove(key);
  void operator []=(K key, V value) {
    _map
      ..remove(key)
      ..[key] = value;
    if (_map.length > capacity) _map.remove(_map.keys.first);
  }
}
