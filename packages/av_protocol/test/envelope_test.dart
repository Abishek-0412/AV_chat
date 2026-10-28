import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:test/test.dart';

void main() {
  const envelope = Envelope(
    id: 'm1',
    from: 'AV-AAAA-BBBB-CCCC',
    to: 'AV-DDDD-EEEE-FFFF',
    type: EnvelopeType.msg,
    body: 'Y2lwaGVydGV4dA==',
  );

  test('encode then decode returns the same envelope', () {
    expect(Envelope.decode(envelope.encode()), envelope);
  });

  test('rejects invalid JSON', () {
    expect(() => Envelope.decode('not json'), throwsFormatException);
  });

  test('rejects non-object JSON', () {
    expect(() => Envelope.decode('[1,2]'), throwsFormatException);
  });

  test('rejects missing fields', () {
    final json = envelope.toJson()..remove('to');
    expect(() => Envelope.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects unknown type', () {
    final json = envelope.toJson()..['type'] = 'spam';
    expect(() => Envelope.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects unsupported version', () {
    final json = envelope.toJson()..['v'] = 99;
    expect(() => Envelope.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects oversized envelopes', () {
    final big = 'x' * (ProtocolLimits.maxEnvelopeBytes + 1);
    expect(() => Envelope.decode(big), throwsFormatException);
  });
}
