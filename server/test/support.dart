import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:av_relay/av_relay.dart';
import 'package:cryptography/cryptography.dart';

final class FakePeer implements RelayPeer {
  final frames = <RelayFrame>[];
  var closed = false;
  @override
  void send(RelayFrame frame) => frames.add(frame);
  @override
  void close() => closed = true;

  T last<T extends RelayFrame>() => frames.whereType<T>().last;
}

final class TestUser {
  TestUser._(this.keyPair, this.publicKey);
  final SimpleKeyPair keyPair;
  final List<int> publicKey;

  String get id => AvId.fromPublicKey(publicKey).value;

  static Future<TestUser> create() async {
    final kp = await Ed25519().newKeyPair();
    final pub = (await kp.extractPublicKey()).bytes;
    return TestUser._(kp, pub);
  }

  HelloFrame hello() => HelloFrame(id: id, publicKey: base64Encode(publicKey));

  Future<AuthFrame> answer(ChallengeFrame challenge) async {
    final sig = await Ed25519().sign(
      base64Decode(challenge.nonce),
      keyPair: keyPair,
    );
    return AuthFrame(signature: base64Encode(sig.bytes));
  }

  Envelope envelopeTo(TestUser other, {String id = 'e1'}) => Envelope(
    id: id,
    from: this.id,
    to: other.id,
    type: EnvelopeType.msg,
    body: 'Y2lwaGVy',
  );
}

/// Runs the full login on [hub]; returns the session and its peer.
Future<(ClientSession, FakePeer)> login(RelayHub hub, TestUser user) async {
  final peer = FakePeer();
  final session = hub.connect(peer);
  await session.onMessage(user.hello().encode());
  final auth = await user.answer(peer.last<ChallengeFrame>());
  await session.onMessage(auth.encode());
  return (session, peer);
}
