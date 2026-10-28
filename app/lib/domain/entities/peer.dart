import 'package:av_protocol/av_protocol.dart';

/// Anyone we may exchange encrypted messages with: a contact or a
/// fellow group member.
final class Peer {
  const Peer({required this.id, required this.name, this.publicKey});

  factory Peer.fromJson(Map<String, Object?> json) => Peer(
    id: AvId.parse(json['id']! as String),
    name: json['name']! as String,
    publicKey: (json['pub'] as List?)?.cast<int>(),
  );

  final AvId id;
  final String name;

  /// Ed25519 identity key. Null until learned from their first handshake
  /// (when added by typing an AV-ID).
  final List<int>? publicKey;

  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    if (publicKey != null) 'pub': publicKey,
  };
}
