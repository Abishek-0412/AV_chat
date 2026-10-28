import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/services/call_service.dart';
import 'package:av_chat/sandbox/fake_call_media.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../support/test_phone.dart';
import '../support/test_user.dart';

final class CallPhone {
  CallPhone(this.phone, FakeMediaNetwork media) {
    this.media = media.forUser(phone.user.id);
    calls = CallService(
      messenger: phone.user.messenger,
      media: this.media,
      groups: phone.groups,
      self: phone.user.id,
      newId: const Uuid().v4,
      ringTimeout: const Duration(seconds: 2),
    )..init();
  }
  final TestPhone phone;
  late final FakeCallMedia media;
  late final CallService calls;
  CallState? get state => calls.call.value;
}

void main() {
  late InMemoryRelayNetwork net;
  late FakeMediaNetwork media;
  late CallPhone alice;
  late CallPhone bob;

  setUp(() async {
    net = InMemoryRelayNetwork();
    media = FakeMediaNetwork();
    final a = await TestPhone.create(net, 'Alice');
    final b = await TestPhone.create(net, 'Bob');
    await TestPhone.befriend(a, b);
    alice = CallPhone(a, media);
    bob = CallPhone(b, media);
  });

  test('1:1 call: ring, accept, connect, hang up', () async {
    await alice.calls.start(DirectRef(bob.phone.user.id));
    await settle();
    expect(alice.state!.phase, CallPhase.calling);
    expect(alice.state!.ringing, isTrue);
    expect(bob.state!.phase, CallPhase.incoming);
    expect(bob.state!.inviter, alice.phone.user.id);

    await bob.calls.accept();
    await settle();
    expect(alice.state!.phase, CallPhase.active);
    expect(bob.state!.phase, CallPhase.active);
    expect(alice.state!.activeSince, isNotNull);

    await alice.calls.hangUp();
    await settle();
    expect(alice.state!.phase, CallPhase.ended);
    expect(bob.state!.phase, CallPhase.ended);
    expect(bob.media.micOpen, isFalse);
  });

  test('decline ends the call for the caller', () async {
    await alice.calls.start(DirectRef(bob.phone.user.id));
    await settle();
    await bob.calls.decline();
    await settle();
    expect(alice.state!.endReason, CallEndReason.declined);
    expect(alice.media.micOpen, isFalse);
  });

  test('offline contact: call is unavailable', () async {
    await bob.phone.user.relay.disconnect();
    await alice.calls.start(DirectRef(bob.phone.user.id));
    await settle();
    expect(alice.state!.endReason, CallEndReason.unavailable);
  });

  test('busy: second caller is told', () async {
    final carol = CallPhone(await TestPhone.create(net, 'Carol'), media);
    await TestPhone.befriend(carol.phone, bob.phone);
    await alice.calls.start(DirectRef(bob.phone.user.id));
    await settle();
    await carol.calls.start(DirectRef(bob.phone.user.id));
    await settle();
    expect(carol.state!.endReason, CallEndReason.busy);
    expect(bob.state!.inviter, alice.phone.user.id);
  });

  test('no answer times out', () async {
    await alice.calls.start(DirectRef(bob.phone.user.id));
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(alice.state!.endReason, CallEndReason.noAnswer);
  });

  test('mute toggles the microphone', () async {
    await alice.calls.start(DirectRef(bob.phone.user.id));
    alice.calls.toggleMute();
    expect(alice.media.muted, isTrue);
    expect(alice.state!.muted, isTrue);
  });

  test('group call: two people join at once, everyone links up', () async {
    final carol = CallPhone(await TestPhone.create(net, 'Carol'), media);
    await TestPhone.befriend(alice.phone, carol.phone);
    final group = await alice.phone.groups.create('Team', [
      alice.phone.contacts.byId(bob.phone.user.id)!.asPeer,
      alice.phone.contacts.byId(carol.phone.user.id)!.asPeer,
    ]);
    await settle();

    await alice.calls.start(GroupRef(group.id));
    await settle();
    expect(bob.state!.phase, CallPhase.incoming);
    expect(carol.state!.phase, CallPhase.incoming);

    // Accept at the same moment.
    await Future.wait([bob.calls.accept(), carol.calls.accept()]);

    final a = alice.phone.user.id;
    final b = bob.phone.user.id;
    final c = carol.phone.user.id;
    await eventually(
      () =>
          alice.state!.connected.length == 2 &&
          bob.state!.connected.length == 2 &&
          carol.state!.connected.length == 2,
    );
    expect(alice.state!.connected, {b, c});
    expect(bob.state!.connected, {a, c});
    expect(carol.state!.connected, {a, b});

    // One leaves; the rest stay connected.
    await carol.calls.hangUp();
    await eventually(() => alice.state!.connected.length == 1);
    expect(alice.state!.phase, CallPhase.active);
    expect(alice.state!.connected, {b});
  });
}
