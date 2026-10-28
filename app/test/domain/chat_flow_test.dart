import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/message.dart';
import 'package:av_chat/domain/user_facing_exception.dart';
import 'package:av_chat/domain/value_objects/message_status.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_phone.dart';
import '../support/test_user.dart';

String textOf(Message m) => (m.content as TextContent).text;

void main() {
  late InMemoryRelayNetwork net;
  late TestPhone alice;
  late TestPhone bob;

  setUp(() async {
    net = InMemoryRelayNetwork();
    alice = await TestPhone.create(net, 'Alice');
    bob = await TestPhone.create(net, 'Bob');
  });

  group('1:1 chat', () {
    setUp(() => TestPhone.befriend(alice, bob));

    test('message arrives and sender sees delivered, then read', () async {
      final toBob = DirectRef(bob.user.id);
      final toAlice = DirectRef(alice.user.id);
      alice.chats.sendText(toBob, '  hello  ');
      await settle();

      final atBob = bob.chats.conversation(toAlice);
      expect(textOf(atBob.messages.single), 'hello');
      expect(atBob.unread, 1);
      expect(
        alice.chats.conversation(toBob).messages.single.status,
        MessageStatus.delivered,
      );

      bob.chats.setOpen(toAlice);
      await settle();
      expect(bob.chats.conversation(toAlice).unread, 0);
      expect(
        alice.chats.conversation(toBob).messages.single.status,
        MessageStatus.read,
      );
    });

    test('open chat reads on arrival', () async {
      bob.chats.setOpen(DirectRef(alice.user.id));
      alice.chats.sendText(DirectRef(bob.user.id), 'hi');
      await settle();
      expect(bob.chats.conversation(DirectRef(alice.user.id)).unread, 0);
      expect(
        alice.chats.conversation(DirectRef(bob.user.id)).messages.single.status,
        MessageStatus.read,
      );
    });

    test('offline contact: message fails', () async {
      await bob.user.relay.disconnect();
      alice.chats.sendText(DirectRef(bob.user.id), 'hello?');
      await settle();
      expect(
        alice.chats.conversation(DirectRef(bob.user.id)).messages.single.status,
        MessageStatus.failed,
      );
    });

    test('typing indicator shows on the other side', () async {
      alice.chats.sendTyping(DirectRef(bob.user.id));
      await settle();
      expect(
        bob.chats.conversation(DirectRef(alice.user.id)).typing,
        {alice.user.id},
      );
    });

    test('reactions and delete-for-everyone sync', () async {
      final toBob = DirectRef(bob.user.id);
      final toAlice = DirectRef(alice.user.id);
      alice.chats.sendText(toBob, 'react to me');
      await settle();
      final id = bob.chats.conversation(toAlice).messages.single.id;

      bob.chats.react(toAlice, id, '👍');
      await settle();
      expect(
        alice.chats.conversation(toBob).messages.single.reactions,
        {bob.user.id: '👍'},
      );

      alice.chats.deleteForEveryone(toBob, id);
      await settle();
      expect(bob.chats.conversation(toAlice).messages.single.deleted, isTrue);
    });

    test('only the author can delete a message', () async {
      final toBob = DirectRef(bob.user.id);
      final toAlice = DirectRef(alice.user.id);
      alice.chats.sendText(toBob, 'mine');
      await settle();
      final id = bob.chats.conversation(toAlice).messages.single.id;
      bob.chats.deleteForEveryone(toAlice, id); // not Bob's message
      await settle();
      expect(alice.chats.conversation(toBob).messages.single.deleted, isFalse);
    });

    test('peer restart: unconfirmed message is resent', () async {
      final toBob = DirectRef(bob.user.id);
      alice.chats.sendText(toBob, 'first');
      await settle();

      // Bob's app restarts; a fresh phone with the same identity.
      await bob.restart();
      alice.chats.sendText(toBob, 'second');
      await settle();
      await settle();

      final atBob = bob.chats.conversation(DirectRef(alice.user.id));
      expect(atBob.messages.map(textOf), ['second']);
      expect(
        alice.chats.conversation(toBob).messages.last.status,
        MessageStatus.delivered,
      );
    });
  });

  test('contact request by AV-ID: accept, then chat', () async {
    await alice.contacts.addById(bob.user.id);
    await settle();
    expect(alice.contacts.byId(bob.user.id)!.isPending, isTrue);
    expect(bob.contacts.requests.value.single.id, alice.user.id);

    await bob.contacts.accept(bob.contacts.requests.value.single);
    await settle();
    final learned = alice.contacts.byId(bob.user.id)!;
    expect(learned.isPending, isFalse);
    expect(learned.name, 'Bob');

    alice.chats.sendText(DirectRef(bob.user.id), 'yay');
    await settle();
    expect(
      textOf(bob.chats.conversation(DirectRef(alice.user.id)).messages.single),
      'yay',
    );
  });

  group('groups', () {
    late TestPhone carol;

    setUp(() async {
      carol = await TestPhone.create(net, 'Carol');
      await TestPhone.befriend(alice, bob);
      await TestPhone.befriend(alice, carol);
    });

    test('owner creates group; members who never met can chat', () async {
      final group = await alice.groups.create('Trip', [
        alice.contacts.byId(bob.user.id)!.asPeer,
        alice.contacts.byId(carol.user.id)!.asPeer,
      ]);
      await settle();
      expect(bob.groups.byId(group.id)!.name, 'Trip');
      expect(carol.groups.byId(group.id)!.members, hasLength(3));

      // Bob and Carol are not contacts, but share the group.
      bob.chats.sendText(GroupRef(group.id), 'hi all');
      await settle();
      expect(
        textOf(carol.chats.conversation(GroupRef(group.id)).messages.single),
        'hi all',
      );
      expect(
        textOf(alice.chats.conversation(GroupRef(group.id)).messages.single),
        'hi all',
      );
      expect(
        bob.chats.conversation(GroupRef(group.id)).messages.single.status,
        MessageStatus.delivered,
      );
    });

    test('removed member drops the group and stops receiving', () async {
      final group = await alice.groups.create('G', [
        alice.contacts.byId(bob.user.id)!.asPeer,
        alice.contacts.byId(carol.user.id)!.asPeer,
      ]);
      await settle();
      await alice.groups.removeMember(group.id, carol.user.id);
      await settle();
      expect(carol.groups.byId(group.id), isNull);
      expect(bob.groups.byId(group.id)!.members, hasLength(2));

      alice.chats.sendText(GroupRef(group.id), 'secret plan');
      await settle();
      expect(carol.chats.conversations.value, isEmpty);
    });

    test('non-owner cannot change the group', () async {
      final group = await alice.groups.create('G', [
        alice.contacts.byId(bob.user.id)!.asPeer,
        alice.contacts.byId(carol.user.id)!.asPeer,
      ]);
      await settle();
      expect(
        () => bob.groups.removeMember(group.id, carol.user.id),
        throwsStateError,
      );
    });

    test('owner leaving hands the group to the next member', () async {
      final group = await alice.groups.create('G', [
        alice.contacts.byId(bob.user.id)!.asPeer,
        alice.contacts.byId(carol.user.id)!.asPeer,
      ]);
      await settle();
      await alice.groups.leave(group.id);
      await settle();
      expect(alice.groups.byId(group.id), isNull);
      final atBob = bob.groups.byId(group.id)!;
      expect(atBob.members.map((m) => m.id), isNot(contains(alice.user.id)));
      expect(atBob.owner, isNot(alice.user.id));
    });

    test('group size is capped at 10', () async {
      final peers = [
        for (var i = 0; i < 10; i++)
          (await TestPhone.create(net, 'P$i')).user.asPeer,
      ];
      expect(
        () => alice.groups.create('Big', peers),
        throwsA(isA<UserFacingException>()),
      );
    });
  });
}
