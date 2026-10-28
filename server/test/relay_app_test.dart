import 'dart:convert';

import 'package:av_relay/av_relay.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final handler = buildRelayHandler();

  test('GET /health reports ok, protocol version and online count', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(res.statusCode, 200);
    expect(jsonDecode(await res.readAsString()), {
      'status': 'ok',
      'protocol': 1,
      'online': 0,
    });
  });

  test('unknown route returns 404', () async {
    final res = await handler(
      Request('GET', Uri.parse('http://localhost/nope')),
    );
    expect(res.statusCode, 404);
  });
}
