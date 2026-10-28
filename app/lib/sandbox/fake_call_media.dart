import 'dart:async';

import 'package:av_chat/domain/services/call_media.dart';
import 'package:av_protocol/av_protocol.dart';

/// Links "connect" when an answer is applied, like real WebRTC.
final class FakeMediaNetwork {
  final _media = <AvId, FakeCallMedia>{};
  FakeCallMedia forUser(AvId id) => _media[id] = FakeCallMedia._(this, id);
}

final class FakeCallMedia implements CallMedia {
  FakeCallMedia._(this._net, this.self);
  final FakeMediaNetwork _net;
  final AvId self;
  final _candidates = StreamController<(AvId, IceCandidate)>.broadcast();
  final _links = StreamController<(AvId, LinkState)>.broadcast();
  final peers = <AvId>{};
  bool micOpen = false;
  bool muted = false;

  @override
  Stream<(AvId, IceCandidate)> get candidates => _candidates.stream;
  @override
  Stream<(AvId, LinkState)> get linkStates => _links.stream;

  @override
  Future<void> openMicrophone() async => micOpen = true;

  @override
  Future<String> createOffer(AvId peer) async {
    peers.add(peer);
    return 'offer:${self.value}>${peer.value}';
  }

  @override
  Future<String> acceptOffer(AvId peer, String offerSdp) async {
    peers.add(peer);
    return 'answer:${self.value}>${peer.value}';
  }

  @override
  Future<void> acceptAnswer(AvId peer, String answerSdp) async {
    _links.add((peer, LinkState.connected));
    _net._media[peer]?._links.add((self, LinkState.connected));
  }

  @override
  Future<void> addCandidate(AvId peer, IceCandidate candidate) async {}

  @override
  Future<void> closePeer(AvId peer) async => peers.remove(peer);

  @override
  Future<void> closeAll() async {
    for (final p in peers.toList()) {
      _net._media[p]?._links.add((self, LinkState.closed));
    }
    peers.clear();
    micOpen = false;
  }

  @override
  void setMuted({required bool muted}) => this.muted = muted;

  @override
  Future<void> setSpeaker({required bool on}) async {}
}
