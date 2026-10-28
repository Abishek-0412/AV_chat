import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'relay_hub.dart';
import 'relay_peer.dart';
import 'signature_verifier.dart';

/// HTTP entry point: `/health` for checks, `/ws` for phones.
Handler buildRelayHandler({RelayHub? hub}) {
  final relay = hub ?? RelayHub(verifier: Ed25519Verifier());
  final router = Router()
    ..get('/health', (Request _) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'protocol': ProtocolLimits.version,
          'online': relay.onlineCount,
        }),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get(
      '/ws',
      webSocketHandler((WebSocketChannel channel, String? _) {
        final session = relay.connect(_ChannelPeer(channel));
        channel.stream.listen(
          (data) {
            if (data is String) session.onMessage(data);
          },
          onDone: session.onClose,
          onError: (Object _) => session.onClose(),
          cancelOnError: true,
        );
      }),
    );
  // Only log method/path/status; never bodies.
  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}

final class _ChannelPeer implements RelayPeer {
  _ChannelPeer(this._channel);
  final WebSocketChannel _channel;

  @override
  void send(RelayFrame frame) => _channel.sink.add(frame.encode());

  @override
  void close() => _channel.sink.close();
}
