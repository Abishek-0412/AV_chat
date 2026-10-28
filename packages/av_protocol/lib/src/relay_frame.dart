import 'dart:convert';

import 'envelope.dart';
import 'protocol_limits.dart';

/// One WebSocket text frame between a phone and the relay.
///
/// Login: client `Hello` → relay `Challenge` → client `Auth` (signature of
/// the nonce) → relay `Ready`. After that: `Send`/`Deliver` move envelopes,
/// `Undeliverable` reports an offline recipient, `Watch`/`Presence`
/// report who is online.
sealed class RelayFrame {
  const RelayFrame();

  String get op;
  Map<String, Object?> get _fields;

  String encode() => jsonEncode({'op': op, ..._fields});

  /// Throws [FormatException] for anything malformed.
  static RelayFrame decode(String raw) {
    if (raw.length > ProtocolLimits.maxEnvelopeBytes + 1024) {
      throw const FormatException('Frame too large');
    }
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Frame is not valid JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('Frame must be a JSON object');
    }
    final r = _Reader(json);
    return switch (r.str('op')) {
      'hello' => HelloFrame(id: r.str('id'), publicKey: r.str('pub')),
      'challenge' => ChallengeFrame(nonce: r.str('nonce')),
      'auth' => AuthFrame(signature: r.str('sig')),
      'ready' => const ReadyFrame(),
      'send' => SendFrame(r.envelope('env')),
      'deliver' => DeliverFrame(r.envelope('env')),
      'undeliverable' => UndeliverableFrame(
        envelopeId: r.str('envId'),
        to: r.str('to'),
      ),
      'watch' => WatchFrame(r.strList('ids')),
      'presence' => PresenceFrame(id: r.str('id'), online: r.boolean('online')),
      'error' => ErrorFrame(r.str('message')),
      final op => throw FormatException('Unknown op: $op'),
    };
  }
}

final class HelloFrame extends RelayFrame {
  const HelloFrame({required this.id, required this.publicKey});
  final String id;

  /// Base64 Ed25519 identity public key.
  final String publicKey;
  @override
  String get op => 'hello';
  @override
  Map<String, Object?> get _fields => {'id': id, 'pub': publicKey};
}

final class ChallengeFrame extends RelayFrame {
  const ChallengeFrame({required this.nonce});

  /// Base64 random bytes the client must sign.
  final String nonce;
  @override
  String get op => 'challenge';
  @override
  Map<String, Object?> get _fields => {'nonce': nonce};
}

final class AuthFrame extends RelayFrame {
  const AuthFrame({required this.signature});

  /// Base64 Ed25519 signature of the challenge nonce bytes.
  final String signature;
  @override
  String get op => 'auth';
  @override
  Map<String, Object?> get _fields => {'sig': signature};
}

final class ReadyFrame extends RelayFrame {
  const ReadyFrame();
  @override
  String get op => 'ready';
  @override
  Map<String, Object?> get _fields => const {};
}

final class SendFrame extends RelayFrame {
  const SendFrame(this.envelope);
  final Envelope envelope;
  @override
  String get op => 'send';
  @override
  Map<String, Object?> get _fields => {'env': envelope.toJson()};
}

final class DeliverFrame extends RelayFrame {
  const DeliverFrame(this.envelope);
  final Envelope envelope;
  @override
  String get op => 'deliver';
  @override
  Map<String, Object?> get _fields => {'env': envelope.toJson()};
}

final class UndeliverableFrame extends RelayFrame {
  const UndeliverableFrame({required this.envelopeId, required this.to});
  final String envelopeId;
  final String to;
  @override
  String get op => 'undeliverable';
  @override
  Map<String, Object?> get _fields => {'envId': envelopeId, 'to': to};
}

final class WatchFrame extends RelayFrame {
  const WatchFrame(this.ids);

  /// AV-IDs whose online status the client wants. Replaces earlier lists.
  final List<String> ids;
  @override
  String get op => 'watch';
  @override
  Map<String, Object?> get _fields => {'ids': ids};
}

final class PresenceFrame extends RelayFrame {
  const PresenceFrame({required this.id, required this.online});
  final String id;
  final bool online;
  @override
  String get op => 'presence';
  @override
  Map<String, Object?> get _fields => {'id': id, 'online': online};
}

final class ErrorFrame extends RelayFrame {
  const ErrorFrame(this.message);
  final String message;
  @override
  String get op => 'error';
  @override
  Map<String, Object?> get _fields => {'message': message};
}

final class _Reader {
  _Reader(this.json);
  final Map<String, Object?> json;

  String str(String key) {
    final v = json[key];
    if (v is! String) throw FormatException('Field "$key" must be a string');
    return v;
  }

  bool boolean(String key) {
    final v = json[key];
    if (v is! bool) throw FormatException('Field "$key" must be a bool');
    return v;
  }

  List<String> strList(String key) {
    final v = json[key];
    if (v is! List || v.any((e) => e is! String)) {
      throw FormatException('Field "$key" must be a list of strings');
    }
    return v.cast<String>();
  }

  Envelope envelope(String key) {
    final v = json[key];
    if (v is! Map<String, Object?>) {
      throw FormatException('Field "$key" must be an object');
    }
    return Envelope.fromJson(v);
  }
}
