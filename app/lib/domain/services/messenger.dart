import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_protocol/av_protocol.dart';

final class Incoming {
  const Incoming(this.from, this.payload);
  final AvId from;
  final WirePayload payload;
}

/// A payload we could not deliver (recipient offline or unreachable).
final class DeliveryFailure {
  const DeliveryFailure(this.to, this.payload);
  final AvId to;
  final WirePayload payload;
}

/// A peer whose identity key we just learned from their handshake.
final class KeyLearned {
  const KeyLearned(this.id, this.name, this.publicKey);
  final AvId id;
  final String name;
  final List<int> publicKey;
}

/// Looks up who we trust. Returns null for strangers.
typedef PeerLookup = Peer? Function(AvId id);

/// End-to-end encrypted messaging on top of the relay. Handles the key
/// exchange per peer, queues payloads until a session exists, and
/// decrypts what arrives.
abstract interface class Messenger {
  Stream<Incoming> get incoming;
  Stream<DeliveryFailure> get failures;

  /// A stranger wants to talk to us.
  Stream<ContactRequest> get requests;

  /// A peer added by AV-ID only has now revealed (and proved) their key.
  Stream<KeyLearned> get keysLearned;

  /// A peer restarted their app; anything they had not confirmed is lost.
  Stream<AvId> get sessionResets;

  /// Who we trust. Called on every incoming handshake.
  void setPeerLookup(PeerLookup lookup);

  /// Our display name, sent inside handshakes.
  void setDisplayName(String name);

  void send(AvId to, WirePayload payload);

  /// Sends a handshake now, e.g. to deliver a contact request.
  void introduce(AvId to);

  /// Accepts a stranger's pending handshake.
  void accept(AvId id);

  /// Forgets everything about [id] (session, queue, pending request).
  void forget(AvId id);
}
