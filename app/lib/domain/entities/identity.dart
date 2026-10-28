import 'package:av_protocol/av_protocol.dart';

/// The local user. The private key never leaves the identity repository.
final class Identity {
  const Identity({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  final AvId id;
  final String name;
  final List<int> publicKey;

  Identity copyWith({String? name}) =>
      Identity(id: id, name: name ?? this.name, publicKey: publicKey);
}
