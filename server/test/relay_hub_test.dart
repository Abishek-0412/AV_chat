import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:av_relay/av_relay.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late RelayHub hub;
  late TestUser alice;
  late TestUser bob;

  setUp(() async {
    hub = RelayHub(verifier: Ed25519Verifier());
    alice = await TestUser.create();
    bob = await TestUser.create();
  });

  test('valid login ends with Ready', () async {
    final (session, peer) = await login(hub, alice);
    expect(session.isReady, isTrue);
    expect(peer.frames.last, isA<ReadyFrame>());
    expect(hub.isOnline(alice.id), isTrue);
  });

  test('wrong signature is rejected', () async {
    final peer = FakePeer();
    final session = hub.connect(peer);
    await session.onMessage(alice.hello().encode());
    // Bob signs Alice's challenge.
    final auth = await bob.answer(peer.last<ChallengeFrame>());
    await session.onMessage(auth.encode());
    expect(peer.closed, isTrue);
    expect(hub.isOnline(alice.id), isFalse);
  });

  test('claiming an AV-ID that does not match the key is rejected', () async {
    final peer = FakePeer();
    final session = hub.connect(peer);
    final hello = HelloFrame(
      id: bob.id,
      publicKey: base64Encode(alice.publicKey),
    );
    await session.onMessage(hello.encode());
    expect(peer.closed, isTrue);
  });

  test('sending before login closes the socket', () async {
    final peer = FakePeer();
    final session = hub.connect(peer);
    await session.onMessage(SendFrame(alice.envelopeTo(bob)).encode());
    expect(peer.closed, isTrue);
  });

  test('envelope is delivered to an online recipient', () async {
    final (a, _) = await login(hub, alice);
    final (_, bobPeer) = await login(hub, bob);
    final env = alice.envelopeTo(bob);
    await a.onMessage(SendFrame(env).encode());
    expect(bobPeer.last<DeliverFrame>().envelope, env);
  });

  test('offline recipient: sender is told, message is dropped', () async {
    final (a, alicePeer) = await login(hub, alice);
    await a.onMessage(SendFrame(alice.envelopeTo(bob)).encode());
    final reply = alicePeer.last<UndeliverableFrame>();
    expect(reply.envelopeId, 'e1');
    expect(reply.to, bob.id);
  });

  test('cannot send as someone else', () async {
    final (a, alicePeer) = await login(hub, alice);
    final (_, bobPeer) = await login(hub, bob);
    final forged = bob.envelopeTo(alice);
    await a.onMessage(SendFrame(forged).encode());
    expect(alicePeer.last<ErrorFrame>().message, contains('Sender'));
    expect(bobPeer.frames.whereType<DeliverFrame>(), isEmpty);
  });

  test('presence: watcher sees online, then offline', () async {
    final (a, alicePeer) = await login(hub, alice);
    await a.onMessage(WatchFrame([bob.id]).encode());
    expect(alicePeer.last<PresenceFrame>().online, isFalse);

    final (b, _) = await login(hub, bob);
    expect(alicePeer.last<PresenceFrame>().online, isTrue);

    b.onClose();
    expect(alicePeer.last<PresenceFrame>().online, isFalse);
    expect(hub.isOnline(bob.id), isFalse);
  });

  test('second login replaces the first socket', () async {
    final (first, firstPeer) = await login(hub, alice);
    final (_, secondPeer) = await login(hub, alice);
    expect(firstPeer.closed, isTrue);
    first.onClose(); // old socket's close must not mark Alice offline
    expect(hub.isOnline(alice.id), isTrue);

    final (b, _) = await login(hub, bob);
    await b.onMessage(SendFrame(bob.envelopeTo(alice)).encode());
    expect(secondPeer.frames.whereType<DeliverFrame>(), hasLength(1));
  });

  test('malformed frame closes the socket', () async {
    final peer = FakePeer();
    await hub.connect(peer).onMessage('garbage');
    expect(peer.closed, isTrue);
  });

  test('login timeout closes idle sockets', () async {
    final quick = RelayHub(
      verifier: Ed25519Verifier(),
      loginTimeout: const Duration(milliseconds: 20),
    );
    final peer = FakePeer();
    quick.connect(peer);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(peer.closed, isTrue);
  });
}
