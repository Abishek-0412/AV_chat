import 'dart:async';
import 'dart:io';

import 'package:av_protocol/av_protocol.dart';
import 'package:av_relay/av_relay.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

import 'support.dart';

/// End-to-end over real sockets.
void main() {
  late HttpServer server;

  setUp(() async {
    server = await io.serve(
      buildRelayHandler(),
      InternetAddress.loopbackIPv4,
      0,
    );
  });

  tearDown(() => server.close(force: true));

  Future<(WebSocket, StreamQueue)> connect(TestUser user) async {
    final ws = await WebSocket.connect('ws://localhost:${server.port}/ws');
    final queue = StreamQueue(ws.map((e) => RelayFrame.decode(e as String)));
    ws.add(user.hello().encode());
    final challenge = await queue.next as ChallengeFrame;
    ws.add((await user.answer(challenge)).encode());
    expect(await queue.next, isA<ReadyFrame>());
    return (ws, queue);
  }

  test('two clients exchange an envelope', () async {
    final alice = await TestUser.create();
    final bob = await TestUser.create();
    final (aliceWs, _) = await connect(alice);
    final (bobWs, bobQueue) = await connect(bob);

    final env = alice.envelopeTo(bob);
    aliceWs.add(SendFrame(env).encode());
    final got = await bobQueue.next as DeliverFrame;
    expect(got.envelope, env);

    await aliceWs.close();
    await bobWs.close();
  });
}

/// Minimal pull-based reader over a stream.
final class StreamQueue {
  StreamQueue(Stream<RelayFrame> stream) {
    stream.listen((f) {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(f);
      } else {
        _buffer.add(f);
      }
    });
  }
  final _buffer = <RelayFrame>[];
  final _waiting = <Completer<RelayFrame>>[];

  Future<RelayFrame> get next {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final c = Completer<RelayFrame>();
    _waiting.add(c);
    return c.future.timeout(const Duration(seconds: 5));
  }
}
