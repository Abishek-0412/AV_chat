import 'package:av_protocol/av_protocol.dart';

/// One connected phone, as seen by the hub. Lets the hub be tested
/// without real sockets.
abstract interface class RelayPeer {
  void send(RelayFrame frame);
  void close();
}
