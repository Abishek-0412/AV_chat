import 'dart:convert';

import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_user.dart';

ChatPayload text(String t, [String id = 'm1']) => ChatPayload(
  messageId: id,
  content: TextContent(t),
  sentAt: DateTime(2026),
);

String textOf(WirePayload p) =>
    ((p as ChatPayload).content as TextContent).text;

void main() {
  late InMemoryRelayNetwork net;
  late TestUser alice;
  late TestUser bob;

  setUp(() async {
    net = InMemoryRelayNetwork();
    alice = await TestUser.create(net, 'Alice');
    bob = await TestUser.create(net, 'Bob');
  });

  test('contacts exchange encrypted messages both ways', () async {
    alice.trust(bob);
    bob.trust(alice);

    final atBob = bob.nextIncoming();
    alice.messenger.send(bob.id, text('hi bob'));
    final got = await atBob;
    expect(got.from, alice.id);
    expect(textOf(got.payload), 'hi bob');

    final atAlice = alice.nextIncoming();
    bob.messenger.send(alice.id, text('hi alice', 'm2'));
    expect(textOf((await atAlice).payload), 'hi alice');
  });

  test('relay only ever sees ciphertext', () async {
    alice.trust(bob);
    bob.trust(alice);
    final atBob = bob.nextIncoming();
    alice.messenger.send(bob.id, text('top secret words'));
    await atBob;
    for (final e in net.traffic) {
      expect(
        utf8.decode(base64Decode(e.body), allowMalformed: true),
        isNot(contains('top secret')),
      );
    }
    expect(net.traffic.map((e) => e.type), contains(EnvelopeType.msg));
  });

  test(
    'stranger handshake becomes a contact request; accept opens chat',
    () async {
      // Alice added Bob by typing his AV-ID: she has no key for him yet.
      alice.trust(bob, withKey: false);
      final request = bob.messenger.requests.first;
      final learned = alice.messenger.keysLearned.first;
      alice.messenger.introduce(bob.id);

      final r = await request.timeout(const Duration(seconds: 3));
      expect(r.id, alice.id);
      expect(r.name, 'Alice');

      bob.trust(alice);
      bob.messenger.accept(alice.id);
      final k = await learned.timeout(const Duration(seconds: 3));
      expect(k.publicKey, bob.identity.publicKey);
      alice.trust(bob);

      final atBob = bob.nextIncoming();
      alice.messenger.send(bob.id, text('accepted!'));
      expect(textOf((await atBob).payload), 'accepted!');
    },
  );

  test('peer restart: session is rebuilt and reported', () async {
    alice.trust(bob);
    bob.trust(alice);
    final first = bob.nextIncoming();
    alice.messenger.send(bob.id, text('before'));
    await first;

    await bob.restart();
    final reset = alice.messenger.sessionResets.first;
    // Alice still has the old session; Bob cannot read it and re-handshakes.
    alice.messenger.send(bob.id, text('lost', 'm2'));
    expect(await reset.timeout(const Duration(seconds: 3)), bob.id);

    final after = bob.nextIncoming();
    alice.messenger.send(bob.id, text('after', 'm3'));
    expect(textOf((await after).payload), 'after');
  });

  test('offline recipient: payload is reported as failed', () async {
    alice.trust(bob);
    bob.trust(alice);
    await bob.relay.disconnect();
    final failure = alice.messenger.failures.first;
    alice.messenger.send(bob.id, text('anyone?'));
    final f = await failure.timeout(const Duration(seconds: 3));
    expect(f.to, bob.id);
    expect(textOf(f.payload), 'anyone?');
  });

  test('tampered ciphertext is dropped', () async {
    alice.trust(bob);
    bob.trust(alice);
    final warmup = bob.nextIncoming();
    alice.messenger.send(bob.id, text('ok'));
    await warmup;

    net.tamper = (e) {
      if (e.type != EnvelopeType.msg) return e;
      final bytes = base64Decode(e.body)..[30] ^= 1;
      return Envelope(
        id: e.id,
        from: e.from,
        to: e.to,
        type: e.type,
        body: base64Encode(bytes),
      );
    };
    var received = 0;
    final sub = bob.messenger.incoming.listen((_) => received++);
    alice.messenger.send(bob.id, text('evil', 'm2'));
    await settle();
    expect(received, 0);
    await sub.cancel();
  });

  test('handshake with a swapped key is refused', () async {
    final mallory = await TestUser.create(net, 'Mallory');
    alice.trust(bob);
    // Bob's contact entry for Alice holds Mallory's key.
    bob.trusted[alice.id] = mallory.asPeer;
    final failure = alice.messenger.failures.first;
    alice.messenger.send(bob.id, text('hello'));
    final f = await failure.timeout(const Duration(seconds: 3));
    expect(f.to, bob.id);
  });

  test('both sides starting at once still converge', () async {
    alice.trust(bob);
    bob.trust(alice);
    final atBob = bob.nextIncoming();
    final atAlice = alice.nextIncoming();
    alice.messenger.send(bob.id, text('a'));
    bob.messenger.send(alice.id, text('b'));
    expect(textOf((await atBob).payload), 'a');
    expect(textOf((await atAlice).payload), 'b');
  });
}
