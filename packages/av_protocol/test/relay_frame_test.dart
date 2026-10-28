import 'package:av_protocol/av_protocol.dart';
import 'package:test/test.dart';

void main() {
  const env = Envelope(
    id: 'e1',
    from: 'AV-AAAA-BBBB-CCCC',
    to: 'AV-DDDD-EEEE-FFFF',
    type: EnvelopeType.handshake,
    body: 'Ym9keQ==',
  );

  final frames = <RelayFrame>[
    const HelloFrame(id: 'AV-AAAA-BBBB-CCCC', publicKey: 'cHVi'),
    const ChallengeFrame(nonce: 'bm9uY2U='),
    const AuthFrame(signature: 'c2ln'),
    const ReadyFrame(),
    const SendFrame(env),
    const DeliverFrame(env),
    const UndeliverableFrame(envelopeId: 'e1', to: 'AV-DDDD-EEEE-FFFF'),
    const WatchFrame(['AV-DDDD-EEEE-FFFF']),
    const PresenceFrame(id: 'AV-DDDD-EEEE-FFFF', online: true),
    const ErrorFrame('boom'),
  ];

  for (final frame in frames) {
    test('${frame.op} survives encode/decode', () {
      final decoded = RelayFrame.decode(frame.encode());
      expect(decoded.runtimeType, frame.runtimeType);
      expect(decoded.encode(), frame.encode());
    });
  }

  test('rejects unknown op', () {
    expect(() => RelayFrame.decode('{"op":"nope"}'), throwsFormatException);
  });

  test('rejects wrong field types', () {
    expect(
      () => RelayFrame.decode('{"op":"presence","id":"x","online":"yes"}'),
      throwsFormatException,
    );
    expect(
      () => RelayFrame.decode('{"op":"watch","ids":[1]}'),
      throwsFormatException,
    );
  });
}
