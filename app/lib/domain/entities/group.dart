import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_protocol/av_protocol.dart';

final class Group {
  const Group({
    required this.id,
    required this.name,
    required this.owner,
    required this.members,
  });

  factory Group.fromJson(Map<String, Object?> json) => Group(
    id: json['id']! as String,
    name: json['name']! as String,
    owner: AvId.parse(json['owner']! as String),
    members: [
      for (final m in json['members']! as List)
        Peer.fromJson((m as Map).cast<String, Object?>()),
    ],
  );

  static const maxMembers = 10;

  final String id;
  final String name;

  /// Only the owner can add or remove members.
  final AvId owner;

  /// Everyone in the group, including the owner and the local user.
  final List<Peer> members;

  bool contains(AvId id) => members.any((m) => m.id == id);

  Group copyWith({String? name, List<Peer>? members}) => Group(
    id: id,
    name: name ?? this.name,
    owner: owner,
    members: members ?? this.members,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'owner': owner.value,
    'members': [for (final m in members) m.toJson()],
  };
}
