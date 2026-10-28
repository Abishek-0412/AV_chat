import 'dart:async';

import 'package:av_chat/data/messaging/secure_messenger.dart';
import 'package:av_chat/data/messaging/session_crypto.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_identity_repository.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:uuid/uuid.dart';

/// A phone in tests: identity + messenger on a fake relay.
final class TestUser {
  TestUser._(this.identity, this.repo, this.network);

  final Identity identity;
  final SecureIdentityRepository repo;
  final InMemoryRelayNetwork network;
  late InMemoryRelayClient relay;
  late SecureMessenger messenger;
  final trusted = <AvId, Peer>{};

  AvId get id => identity.id;
  Peer get asPeer =>
      Peer(id: id, name: identity.name, publicKey: identity.publicKey);

  static Future<TestUser> create(InMemoryRelayNetwork net, String name) async {
    final repo = SecureIdentityRepository(MemoryKeyValueStore());
    final identity = await repo.create(name);
    final user = TestUser._(identity, repo, net);
    await user.start();
    return user;
  }

  /// Fresh app run: new ephemeral key, empty memory, same identity.
  Future<void> start({Duration timeout = const Duration(seconds: 1)}) async {
    relay = network.client(id.value);
    messenger =
        SecureMessenger(
            relay: relay,
            self: identity,
            sign: repo.sign,
            crypto: await SessionCrypto.create(),
            newId: const Uuid().v4,
            handshakeTimeout: timeout,
          )
          ..setPeerLookup((id) => trusted[id])
          ..start();
    await relay.connect('fake');
  }

  Future<void> restart() async {
    await relay.disconnect();
    await messenger.dispose();
    await start();
  }

  void trust(TestUser other, {bool withKey = true}) {
    trusted[other.id] = withKey
        ? other.asPeer
        : Peer(id: other.id, name: other.identity.name);
  }

  Future<Incoming> nextIncoming() =>
      messenger.incoming.first.timeout(const Duration(seconds: 3));
}

/// Lets queued async work (crypto, microtasks) finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));

/// Waits until [condition] holds (or fails after [timeout]). Use instead
/// of a fixed delay when several handshakes must finish first.
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
