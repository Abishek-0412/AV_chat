import 'dart:async';

import 'package:av_chat/data/messaging/secure_messenger.dart';
import 'package:av_chat/data/messaging/session_crypto.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_contact_repository.dart';
import 'package:av_chat/data/secure/secure_group_repository.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/repositories/identity_repository.dart';
import 'package:av_chat/domain/services/call_media.dart';
import 'package:av_chat/domain/services/call_service.dart';
import 'package:av_chat/domain/services/chat_service.dart';
import 'package:av_chat/domain/services/contact_service.dart';
import 'package:av_chat/domain/services/group_service.dart';
import 'package:av_chat/domain/services/presence_service.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:uuid/uuid.dart';

/// Everything that lives while the app runs with an identity. Built once
/// after unlock; gone (with every message) when the process ends.
final class AppSession {
  AppSession._({
    required this.identity,
    required this.relay,
    required this.messenger,
    required this.contacts,
    required this.groups,
    required this.chats,
    required this.presence,
    required this.calls,
  });

  final Identity identity;
  final RelayClient relay;
  final SecureMessenger messenger;
  final ContactService contacts;
  final GroupService groups;
  final ChatService chats;
  final PresenceService presence;
  final CallService calls;
  final _subs = <StreamSubscription<Object?>>[];

  static Future<AppSession> start({
    required Identity identity,
    required IdentityRepository identities,
    required KeyValueStore store,
    required RelayClient relay,
    required String relayUrl,
    required CallMedia callMedia,
  }) async {
    const uuid = Uuid();
    final messenger = SecureMessenger(
      relay: relay,
      self: identity,
      sign: identities.sign,
      crypto: await SessionCrypto.create(),
      newId: uuid.v4,
    )..start();
    final contacts = ContactService(
      SecureContactRepository(store),
      messenger,
      identity.id,
    );
    final groups = GroupService(
      SecureGroupRepository(store),
      messenger,
      identity,
      uuid.v4,
    );
    final chats = ChatService(
      messenger: messenger,
      groups: groups,
      self: identity.id,
      newId: uuid.v4,
    );
    final presence = PresenceService(relay);
    final calls = CallService(
      messenger: messenger,
      media: callMedia,
      groups: groups,
      self: identity.id,
      newId: uuid.v4,
    );
    await contacts.init();
    await groups.init();
    chats.init();
    presence.init();
    calls.init();
    messenger.setPeerLookup(
      (id) => contacts.byId(id)?.asPeer ?? groups.memberById(id),
    );
    final session = AppSession._(
      identity: identity,
      relay: relay,
      messenger: messenger,
      contacts: contacts,
      groups: groups,
      chats: chats,
      presence: presence,
      calls: calls,
    ).._wire();
    unawaited(relay.connect(relayUrl));
    return session;
  }

  void _wire() {
    _subs
      // Follow presence of everyone we know.
      ..add(contacts.contacts.stream.listen((_) => _updateWatchList()))
      ..add(groups.groups.stream.listen((_) => _updateWatchList()))
      // Pending requests are re-sent as soon as the person comes online.
      ..add(
        presence.online.stream.listen((online) {
          for (final c in contacts.contacts.value) {
            if (c.isPending && online.contains(c.id)) {
              messenger.introduce(c.id);
            }
          }
        }),
      );
  }

  void _updateWatchList() {
    final ids = <AvId>{
      for (final c in contacts.contacts.value) c.id,
      for (final g in groups.groups.value)
        for (final m in g.members)
          if (m.id != identity.id) m.id,
    };
    presence.follow(ids);
  }

  void rename(String name) => messenger.setDisplayName(name);

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await calls.dispose();
    await chats.dispose();
    await groups.dispose();
    await contacts.dispose();
    await presence.dispose();
    await messenger.dispose();
    await relay.disconnect();
  }
}
