/// Limits both sides enforce on the wire.
abstract final class ProtocolLimits {
  /// Current envelope format version.
  static const int version = 1;

  /// Largest encoded envelope accepted by the relay (2 MB).
  static const int maxEnvelopeBytes = 2 * 1024 * 1024;
}
