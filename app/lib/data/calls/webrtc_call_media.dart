import 'dart:async';

import 'package:av_chat/domain/services/call_media.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Audio-only WebRTC. Media is encrypted peer-to-peer with DTLS-SRTP;
/// the offer/answer carrying the DTLS fingerprints travels inside our
/// end-to-end encrypted channel, so the relay cannot intercept it.
final class WebRtcCallMedia implements CallMedia {
  WebRtcCallMedia({List<Map<String, Object>>? iceServers})
    : _iceServers = iceServers ?? defaultIceServers;

  /// STUN helps across different networks; on the same Wi-Fi it is not
  /// even needed. A TURN server can be added for strict mobile networks.
  static const defaultIceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  final List<Map<String, Object>> _iceServers;
  final _peers = <AvId, RTCPeerConnection>{};
  final _pendingCandidates = <AvId, List<RTCIceCandidate>>{};
  final _candidates = StreamController<(AvId, IceCandidate)>.broadcast();
  final _links = StreamController<(AvId, LinkState)>.broadcast();
  MediaStream? _mic;
  var _muted = false;

  @override
  Stream<(AvId, IceCandidate)> get candidates => _candidates.stream;
  @override
  Stream<(AvId, LinkState)> get linkStates => _links.stream;

  @override
  Future<void> openMicrophone() async {
    if (_mic != null) return;
    if (!await Permission.microphone.request().isGranted) {
      throw StateError('Microphone permission denied');
    }
    _mic = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _applyMute();
    await Helper.setSpeakerphoneOn(false);
  }

  @override
  Future<String> createOffer(AvId peer) async {
    final pc = await _connection(peer);
    final offer = await pc.createOffer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(offer);
    return offer.sdp!;
  }

  @override
  Future<String> acceptOffer(AvId peer, String offerSdp) async {
    final pc = await _connection(peer);
    await pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    await _flushCandidates(peer, pc);
    final answer = await pc.createAnswer({'offerToReceiveAudio': true});
    await pc.setLocalDescription(answer);
    return answer.sdp!;
  }

  @override
  Future<void> acceptAnswer(AvId peer, String answerSdp) async {
    final pc = _peers[peer];
    if (pc == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
    await _flushCandidates(peer, pc);
  }

  @override
  Future<void> addCandidate(AvId peer, IceCandidate c) async {
    final candidate = RTCIceCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex);
    final pc = _peers[peer];
    // Candidates may arrive before the remote description: hold them.
    if (pc == null || await pc.getRemoteDescription() == null) {
      (_pendingCandidates[peer] ??= []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  @override
  Future<void> closePeer(AvId peer) async {
    _pendingCandidates.remove(peer);
    final pc = _peers.remove(peer);
    if (pc == null) return;
    pc
      ..onConnectionState = null
      ..onIceCandidate = null;
    await pc.close();
  }

  @override
  Future<void> closeAll() async {
    for (final peer in _peers.keys.toList()) {
      await closePeer(peer);
    }
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _mic?.dispose();
    _mic = null;
    _muted = false;
    await Helper.setSpeakerphoneOn(false);
  }

  @override
  void setMuted({required bool muted}) {
    _muted = muted;
    _applyMute();
  }

  @override
  Future<void> setSpeaker({required bool on}) => Helper.setSpeakerphoneOn(on);

  void _applyMute() {
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
  }

  Future<RTCPeerConnection> _connection(AvId peer) async {
    final existing = _peers[peer];
    if (existing != null) return existing;
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _peers[peer] = pc;
    final mic = _mic;
    if (mic != null) {
      for (final track in mic.getAudioTracks()) {
        await pc.addTrack(track, mic);
      }
    }
    pc
      ..onIceCandidate = (c) {
        if (c.candidate == null) return;
        _candidates.add((
          peer,
          IceCandidate(c.candidate!, c.sdpMid, c.sdpMLineIndex),
        ));
      }
      ..onConnectionState = (state) {
        final link = switch (state) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
            LinkState.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
            LinkState.failed,
          RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
            LinkState.closed,
          _ => LinkState.connecting,
        };
        _links.add((peer, link));
      };
    return pc;
  }

  Future<void> _flushCandidates(AvId peer, RTCPeerConnection pc) async {
    for (final c
        in _pendingCandidates.remove(peer) ?? const <RTCIceCandidate>[]) {
      await pc.addCandidate(c);
    }
  }
}
