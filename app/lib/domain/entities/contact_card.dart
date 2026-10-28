import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:crypto/crypto.dart';

/// What a QR code carries: enough to add someone and trust their key.
final class ContactCard {
  const ContactCard({
    required this.id,
    required this.name,
    required this.publicKey,
  });

  static const _prefix = 'avchat:';

  final AvId id;
  final String name;
  final List<int> publicKey;

  String encode() =>
      _prefix +
      base64Url.encode(
        utf8.encode(
          jsonEncode({
            'id': id.value,
            'name': name,
            'pub': base64Encode(publicKey),
          }),
        ),
      );

  /// Returns null unless [raw] is a well-formed card whose AV-ID really
  /// belongs to its public key.
  static ContactCard? tryDecode(String raw) {
    if (!raw.startsWith(_prefix)) return null;
    try {
      final json =
          jsonDecode(
                utf8.decode(base64Url.decode(raw.substring(_prefix.length))),
              )
              as Map<String, Object?>;
      final pub = base64Decode(json['pub']! as String);
      final id = AvId.parse(json['id']! as String);
      if (AvId.fromPublicKey(pub) != id) return null;
      return ContactCard(id: id, name: json['name']! as String, publicKey: pub);
    } on Object {
      return null;
    }
  }
}

/// 60-digit code both people compare in person. Same on both phones,
/// changes if either key is swapped by a man-in-the-middle.
String safetyCode(List<int> keyA, List<int> keyB) {
  final a = base64Encode(keyA);
  final b = base64Encode(keyB);
  final ordered = a.compareTo(b) < 0 ? [keyA, keyB] : [keyB, keyA];
  final digest = sha512.convert([...ordered[0], ...ordered[1]]).bytes;
  final groups = <String>[];
  for (var i = 0; i < 12; i++) {
    final chunk = digest.sublist(i * 5, i * 5 + 5);
    final n = chunk.fold<int>(0, (acc, b) => (acc << 8) | b) % 100000;
    groups.add(n.toString().padLeft(5, '0'));
  }
  return groups.join(' ');
}
