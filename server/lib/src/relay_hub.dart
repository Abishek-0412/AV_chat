import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:av_protocol/av_protocol.dart';

import 'rate_limiter.dart';
import 'relay_peer.dart';
import 'signature_verifier.dart';

/// Routes encrypted envelopes between online users. Holds everything in
/// memory and writes nothing anywhere: when a user goes offline, the
/// hub forgets them.
final class RelayHub {
  RelayHub({
    required SignatureVerifier verifier,
    Random? random,
    this.loginTimeout = const Duration(seconds: 15),
  }) : _verifier = verifier,
       _random = random ?? Random.secure();

  /// Sockets that have not finished logging in by then are closed.
  final Duration loginTimeout;

  final SignatureVerifier _verifier;
  final Random _random;
  final _online = <String, ClientSession>{};
  final _watchers = <String, Set<ClientSession>>{};

  int get onlineCount => _online.length;

  ClientSession connect(RelayPeer peer) {
    final session = ClientSession._(this, peer);
    session._loginTimer = Timer(loginTimeout, () {
      if (!session.isReady) session._fail('Login timeout');
    });
    return session;
  }

  bool isOnline(String id) => _online.containsKey(id);

  List<int> _nonce() => List<int>.generate(32, (_) => _random.nextInt(256));

  void _register(ClientSession session) {
    // A newer login from the same phone replaces the old socket.
    final previous = _online[session.id];
    if (previous != null) {
      previous._detached = true;
      previous._peer.close();
    }
    _online[session.id!] = session;
    if (previous == null) _broadcastPresence(session.id!, online: true);
  }

  void _unregister(ClientSession session) {
    _setWatch(session, const []);
    if (session._detached || session.id == null) return;
    if (_online[session.id] == session) {
      _online.remove(session.id);
      _broadcastPresence(session.id!, online: false);
    }
  }

  void _setWatch(ClientSession session, List<String> ids) {
    for (final id in session._watching) {
      _watchers[id]?.remove(session);
      if (_watchers[id]?.isEmpty ?? false) _watchers.remove(id);
    }
    session._watching
      ..clear()
      ..addAll(ids.take(_maxWatch));
    for (final id in session._watching) {
      (_watchers[id] ??= {}).add(session);
      session._peer.send(PresenceFrame(id: id, online: isOnline(id)));
    }
  }

  void _broadcastPresence(String id, {required bool online}) {
    for (final watcher in _watchers[id] ?? const <ClientSession>{}) {
      watcher._peer.send(PresenceFrame(id: id, online: online));
    }
  }

  void _route(ClientSession sender, Envelope envelope) {
    final target = _online[envelope.to];
    if (target == null) {
      sender._peer.send(
        UndeliverableFrame(envelopeId: envelope.id, to: envelope.to),
      );
      return;
    }
    target._peer.send(DeliverFrame(envelope));
  }

  static const _maxWatch = 500;
}

enum _Stage { awaitingHello, awaitingAuth, ready }

/// One socket's lifecycle: login handshake, then routing.
final class ClientSession {
  ClientSession._(this._hub, this._peer);

  final RelayHub _hub;
  final RelayPeer _peer;
  final _limiter = RateLimiter();
  final _watching = <String>{};
  var _stage = _Stage.awaitingHello;
  var _detached = false;
  Timer? _loginTimer;
  String? id;
  List<int>? _publicKey;
  List<int>? _nonce;

  bool get isReady => _stage == _Stage.ready;

  Future<void> onMessage(String raw) async {
    if (!_limiter.tryTake()) {
      _fail('Rate limit exceeded');
      return;
    }
    final RelayFrame frame;
    try {
      frame = RelayFrame.decode(raw);
    } on FormatException catch (e) {
      _fail(e.message);
      return;
    }
    switch ((_stage, frame)) {
      case (_Stage.awaitingHello, HelloFrame(:final id, :final publicKey)):
        await _onHello(id, publicKey);
      case (_Stage.awaitingAuth, AuthFrame(:final signature)):
        await _onAuth(signature);
      case (_Stage.ready, SendFrame(:final envelope)):
        if (envelope.from != id) {
          _peer.send(const ErrorFrame('Sender does not match login'));
          return;
        }
        _hub._route(this, envelope);
      case (_Stage.ready, WatchFrame(:final ids)):
        _hub._setWatch(this, ids);
      default:
        _fail('Unexpected ${frame.op}');
    }
  }

  void onClose() {
    _loginTimer?.cancel();
    _hub._unregister(this);
  }

  Future<void> _onHello(String claimedId, String publicKeyB64) async {
    final List<int> key;
    try {
      key = base64Decode(publicKeyB64);
    } on FormatException {
      _fail('Bad public key');
      return;
    }
    if (key.length != 32 || AvId.fromPublicKey(key).value != claimedId) {
      _fail('AV-ID does not match public key');
      return;
    }
    id = claimedId;
    _publicKey = key;
    _nonce = _hub._nonce();
    _stage = _Stage.awaitingAuth;
    _peer.send(ChallengeFrame(nonce: base64Encode(_nonce!)));
  }

  Future<void> _onAuth(String signatureB64) async {
    final List<int> signature;
    try {
      signature = base64Decode(signatureB64);
    } on FormatException {
      _fail('Bad signature');
      return;
    }
    final ok = await _hub._verifier.verify(
      message: _nonce!,
      signature: signature,
      publicKey: _publicKey!,
    );
    if (!ok) {
      _fail('Signature check failed');
      return;
    }
    _stage = _Stage.ready;
    _loginTimer?.cancel();
    _hub._register(this);
    _peer.send(const ReadyFrame());
  }

  void _fail(String message) {
    _peer
      ..send(ErrorFrame(message))
      ..close();
  }
}
