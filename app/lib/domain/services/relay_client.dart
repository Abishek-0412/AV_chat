import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';

/// Socket to the relay: login, reconnect, raw envelopes and presence.
abstract interface class RelayClient {
  Stream<ConnectionStatus> get status;
  ConnectionStatus get currentStatus;

  Stream<Envelope> get envelopes;
  Stream<UndeliverableFrame> get undeliverable;
  Stream<PresenceFrame> get presence;

  /// Connects and keeps reconnecting until [disconnect].
  Future<void> connect(String url);
  Future<void> disconnect();

  /// Returns false if not currently online.
  bool send(Envelope envelope);

  /// Replaces the set of AV-IDs whose presence we follow.
  void watch(Iterable<String> ids);
}
