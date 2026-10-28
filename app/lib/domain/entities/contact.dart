import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_protocol/av_protocol.dart';

final class Contact {
  const Contact({
    required this.id,
    required this.name,
    this.publicKey,
    this.verified = false,
  });

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
    id: AvId.parse(json['id']! as String),
    name: json['name']! as String,
    publicKey: (json['pub'] as List?)?.cast<int>(),
    verified: json['verified'] as bool? ?? false,
  );

  final AvId id;
  final String name;

  /// Null while waiting for them to accept (added by typed AV-ID).
  final List<int>? publicKey;

  /// True once both people compared safety codes in person.
  final bool verified;

  bool get isPending => publicKey == null;

  Peer get asPeer => Peer(id: id, name: name, publicKey: publicKey);

  Contact copyWith({String? name, List<int>? publicKey, bool? verified}) =>
      Contact(
        id: id,
        name: name ?? this.name,
        publicKey: publicKey ?? this.publicKey,
        verified: verified ?? this.verified,
      );

  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    if (publicKey != null) 'pub': publicKey,
    'verified': verified,
  };
}

/// Someone who wants to add us. Lives in memory only until accepted.
final class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  final AvId id;
  final String name;
  final List<int> publicKey;
}
