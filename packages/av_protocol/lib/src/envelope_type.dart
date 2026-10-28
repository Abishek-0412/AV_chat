/// What an envelope carries. Deliberately coarse: chat text, receipts,
/// typing and call signaling all travel as encrypted [msg] envelopes, so
/// the relay cannot tell them apart.
enum EnvelopeType {
  /// Signed key exchange that sets up an end-to-end session.
  handshake,

  /// Anything encrypted with an established session.
  msg;

  static EnvelopeType parse(String value) => EnvelopeType.values.firstWhere(
    (t) => t.name == value,
    orElse: () => throw FormatException('Unknown envelope type: $value'),
  );
}
