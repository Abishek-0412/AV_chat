import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_contact_repository.dart';
import 'package:av_chat/data/secure/secure_group_repository.dart';
import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/services/chat_service.dart';
import 'package:av_chat/domain/services/contact_service.dart';
import 'package:av_chat/domain/services/group_service.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:uuid/uuid.dart';

import 'test_user.dart';

/// A whole app (minus UI) on the fake relay.
final class TestPhone {
  TestPhone._(this.user);
  final TestUser user;
  late ContactService contacts;
  late GroupService groups;
  late ChatService chats;

  static Future<TestPhone> create(InMemoryRelayNetwork net, String name) async {
    final phone = TestPhone._(await TestUser.create(net, name));
    await phone._wire();
    return phone;
  }

  /// Survives restarts, like the encrypted storage on a real phone.
  final _store = MemoryKeyValueStore();

  /// App restart: memory (chats, sessions) is gone, storage is kept.
  Future<void> restart() async {
    await chats.dispose();
    await groups.dispose();
    await contacts.dispose();
    await user.restart();
    await _wire();
  }

  Future<void> _wire() async {
    final store = _store;
    final m = user.messenger;
    contacts = ContactService(SecureContactRepository(store), m, user.id);
    groups = GroupService(
      SecureGroupRepository(store),
      m,
      user.identity,
      const Uuid().v4,
    );
    chats = ChatService(
      messenger: m,
      groups: groups,
      self: user.id,
      newId: const Uuid().v4,
    );
    await contacts.init();
    await groups.init();
    chats.init();
    m.setPeerLookup(
      (id) => contacts.byId(id)?.asPeer ?? groups.memberById(id),
    );
  }

  ContactCard get card => ContactCard(
    id: user.id,
    name: user.identity.name,
    publicKey: user.identity.publicKey,
  );

  /// Both scan each other's QR code.
  static Future<void> befriend(TestPhone a, TestPhone b) async {
    await a.contacts.addFromCard(b.card);
    await b.contacts.addFromCard(a.card);
    await settle();
  }
}
