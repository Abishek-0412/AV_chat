import 'dart:async';
import 'dart:convert';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/data/messaging/secure_messenger.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Keeps one authenticated WebSocket to the relay, reconnecting with
/// backoff (1 s → 15 s) whenever it drops.
final class WebSocketRelayClient implements RelayClient {
  WebSocketRelayClient({required Identity self, required Signer sign})
    : _self = self,
      _sign = sign;

  final Identity _self;
  final Signer _sign;
  final Store<ConnectionStatus> _status = Store(ConnectionStatus.offline);
  final _envelopes = StreamController<Envelope>.broadcast();
  final _undeliverable = StreamController<UndeliverableFrame>.broadcast();
  final _presence = StreamController<PresenceFrame>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _sub;
  Timer? _retry;
  Uri? _uri;
  var _wanted = false;
  var _attempt = 0;
  Set<String> _watched = const {};

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

  /// Accepts `ws://host:port` and adds the `/ws` path when missing.
  static Uri normalize(String url) {
    var uri = Uri.parse(url.trim());
    if (!uri.hasScheme) uri = Uri.parse('ws://${url.trim()}');
    if (uri.path.isEmpty || uri.path == '/') uri = uri.replace(path: '/ws');
    return uri;
  }

  @override
  Future<void> connect(String url) async {
    final uri = normalize(url);
    if (_wanted && uri == _uri) return;
    await disconnect();
    _uri = uri;
    _wanted = true;
    _attempt = 0;
    await _open();
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _retry?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.offline);
  }

  @override
  bool send(Envelope envelope) {
    if (_status.value != ConnectionStatus.online) return false;
    _channel?.sink.add(SendFrame(envelope).encode());
    return true;
  }

  @override
  void watch(Iterable<String> ids) {
    _watched = ids.toSet();
    if (_status.value == ConnectionStatus.online) {
      _channel?.sink.add(WatchFrame(_watched.toList()).encode());
    }
  }

  Future<void> _open() async {
    if (!_wanted || _uri == null) return;
    _setStatus(ConnectionStatus.connecting);
    final channel = IOWebSocketChannel.connect(
      _uri!,
      pingInterval: const Duration(seconds: 15),
      connectTimeout: const Duration(seconds: 10),
    );
    _channel = channel;
    try {
      await channel.ready;
    } on Object catch (e) {
      debugPrint('[relay] connect failed: $e');
      _scheduleRetry();
      return;
    }
    _sub = channel.stream.listen(
      (data) {
        if (data is String) unawaited(_onFrame(channel, data));
      },
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
      cancelOnError: true,
    );
    channel.sink.add(
      HelloFrame(
        id: _self.id.value,
        publicKey: base64Encode(_self.publicKey),
      ).encode(),
    );
  }

  Future<void> _onFrame(WebSocketChannel channel, String raw) async {
    final RelayFrame frame;
    try {
      frame = RelayFrame.decode(raw);
    } on FormatException {
      return;
    }
    switch (frame) {
      case ChallengeFrame(:final nonce):
        final sig = await _sign(base64Decode(nonce));
        channel.sink.add(AuthFrame(signature: base64Encode(sig)).encode());
      case ReadyFrame():
        _attempt = 0;
        _setStatus(ConnectionStatus.online);
        if (_watched.isNotEmpty) {
          channel.sink.add(WatchFrame(_watched.toList()).encode());
        }
      case DeliverFrame(:final envelope):
        _envelopes.add(envelope);
      case final UndeliverableFrame u:
        _undeliverable.add(u);
      case final PresenceFrame p:
        _presence.add(p);
      case ErrorFrame(:final message):
        debugPrint('[relay] error: $message');
      case HelloFrame() || AuthFrame() || SendFrame() || WatchFrame():
        break; // client-to-server only
    }
  }

  void _onClosed() {
    _channel = null;
    if (_wanted) {
      _scheduleRetry();
    } else {
      _setStatus(ConnectionStatus.offline);
    }
  }

  void _scheduleRetry() {
    _setStatus(ConnectionStatus.connecting);
    _retry?.cancel();
    final seconds = [1, 2, 4, 8, 15][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _setStatus(ConnectionStatus s) {
    if (_status.value != s) _status.value = s;
  }
}
