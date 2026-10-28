import 'dart:convert';

import 'envelope_type.dart';
import 'protocol_limits.dart';

/// The only thing the relay ever sees: routing fields plus an opaque,
/// end-to-end encrypted [body] (base64).
final class Envelope {
  const Envelope({
    required this.id,
    required this.from,
    required this.to,
    required this.type,
    required this.body,
    this.version = ProtocolLimits.version,
  });

  final int version;
  final String id;
  final String from;
  final String to;
  final EnvelopeType type;
  final String body;

  Map<String, Object> toJson() => {
    'v': version,
    'id': id,
    'from': from,
    'to': to,
    'type': type.name,
    'body': body,
  };

  String encode() => jsonEncode(toJson());

  /// Throws [FormatException] for anything malformed or oversized.
  static Envelope decode(String raw) {
    if (raw.length > ProtocolLimits.maxEnvelopeBytes) {
      throw const FormatException('Envelope too large');
    }
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Envelope is not valid JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Envelope must be a JSON object');
    }
    return Envelope.fromJson(json);
  }

  /// Throws [FormatException] for missing or wrongly typed fields.
  static Envelope fromJson(Map<String, Object?> json) {
    final version = json['v'];
    if (version != ProtocolLimits.version) {
      throw FormatException('Unsupported envelope version: $version');
    }
    final body = _string(json, 'body');
    if (body.length > ProtocolLimits.maxEnvelopeBytes) {
      throw const FormatException('Envelope too large');
    }
    return Envelope(
      id: _string(json, 'id'),
      from: _string(json, 'from'),
      to: _string(json, 'to'),
      type: EnvelopeType.parse(_string(json, 'type')),
      body: body,
    );
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('Field "$key" must be a string');
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is Envelope &&
      other.version == version &&
      other.id == id &&
      other.from == from &&
      other.to == to &&
      other.type == type &&
      other.body == body;

  @override
  int get hashCode => Object.hash(version, id, from, to, type, body);
}
