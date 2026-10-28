import 'package:av_protocol/av_protocol.dart';

final class IceCandidate {
  const IceCandidate(this.candidate, this.sdpMid, this.sdpMLineIndex);
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

enum LinkState { connecting, connected, failed, closed }

/// Audio links to one or more peers (WebRTC in the app, fake in tests).
abstract interface class CallMedia {
  Stream<(AvId, IceCandidate)> get candidates;
  Stream<(AvId, LinkState)> get linkStates;

  /// Mic stream is shared by all links.
  Future<void> openMicrophone();

  Future<String> createOffer(AvId peer);
  Future<String> acceptOffer(AvId peer, String offerSdp);
  Future<void> acceptAnswer(AvId peer, String answerSdp);
  Future<void> addCandidate(AvId peer, IceCandidate candidate);

  /// Closes one link. Must not emit a [LinkState] for it.
  Future<void> closePeer(AvId peer);

  /// Ends every link and releases the microphone.
  Future<void> closeAll();

  void setMuted({required bool muted});
  Future<void> setSpeaker({required bool on});
}
