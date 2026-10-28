import 'package:crypto/crypto.dart';

/// A user's public address, derived from their Ed25519 identity key:
/// `AV-` + first 60 bits of SHA-256(publicKey) in Base32, grouped 4-4-4.
///
/// Because it is a hash of the key, nobody can claim an AV-ID without
/// holding the matching private key.
extension type const AvId._(String value) {
  /// Parses and validates user input such as `av-7k3m qx9p 2hfd`.
  /// Returns null if it is not a valid AV-ID.
  static AvId? tryParse(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');
    final body = clean.startsWith('AV') ? clean.substring(2) : clean;
    if (body.length != _length || !_isBase32(body)) return null;
    return AvId._(_format(body));
  }

  /// Throws [FormatException] if [input] is not a valid AV-ID.
  static AvId parse(String input) =>
      tryParse(input) ?? (throw FormatException('Invalid AV-ID: $input'));

  static AvId fromPublicKey(List<int> publicKey) {
    final digest = sha256.convert(publicKey).bytes;
    return AvId._(_format(_base32(digest).substring(0, _length)));
  }

  static const _length = 12;
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static bool _isBase32(String s) => s.split('').every(_alphabet.contains);

  static String _format(String body) =>
      'AV-${body.substring(0, 4)}-${body.substring(4, 8)}-${body.substring(8)}';

  static String _base32(List<int> bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }
}
