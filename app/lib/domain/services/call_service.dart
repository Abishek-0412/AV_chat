import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/domain/services/call_media.dart';
import 'package:av_chat/domain/services/group_service.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_protocol/av_protocol.dart';

enum CallPhase {
  /// We invited; nobody has joined yet.
  calling,

  /// Someone is inviting us.
  incoming,

  /// Audio links are being set up.
  connecting,

  /// At least one person is connected.
  active,

  ended,
}

enum CallEndReason { hungUp, declined, busy, unavailable, noAnswer, failed }

final class CallState {
  const CallState({
    required this.callId,
    required this.conversation,
    required this.inviter,
    required this.phase,
    this.connected = const {},
    this.joined = const {},
    this.ringing = false,
    this.muted = false,
    this.speaker = false,
    this.activeSince,
    this.endReason,
  });

  final String callId;
  final ConversationRef conversation;
  final AvId inviter;
  final CallPhase phase;

  /// Peers whose audio link is up.
  final Set<AvId> connected;

  /// Peers who accepted (link may still be connecting).
  final Set<AvId> joined;

  /// Remote phone confirmed it is ringing (1:1 outgoing).
  final bool ringing;
  final bool muted;
  final bool speaker;
  final DateTime? activeSince;
  final CallEndReason? endReason;

  bool get isGroup => conversation is GroupRef;

  CallState copyWith({
    CallPhase? phase,
    Set<AvId>? connected,
    Set<AvId>? joined,
    bool? ringing,
    bool? muted,
    bool? speaker,
    DateTime? activeSince,
    CallEndReason? endReason,
  }) => CallState(
    callId: callId,
    conversation: conversation,
    inviter: inviter,
    phase: phase ?? this.phase,
    connected: connected ?? this.connected,
    joined: joined ?? this.joined,
    ringing: ringing ?? this.ringing,
    muted: muted ?? this.muted,
    speaker: speaker ?? this.speaker,
    activeSince: activeSince ?? this.activeSince,
    endReason: endReason ?? this.endReason,
  );
}

/// Voice calls for 1:1 chats and groups (full mesh: everyone links to
/// everyone, fine for the 10-person cap).
///
/// Signaling (all end-to-end encrypted):
///   inviter → members: invite        member → inviter: ringing
///   joiner  → all:     accept        in-call peer → joiner: offer
///   joiner  → peer:    answer        both: ice …   anyone: hangup
/// The peer already in the call always makes the offer, so two phones
/// never offer to each other at once.
final class CallService {
  CallService({
    required Messenger messenger,
    required CallMedia media,
    required GroupService groups,
    required AvId self,
    required String Function() newId,
    DateTime Function()? clock,
    this.ringTimeout = const Duration(seconds: 45),
  }) : _messenger = messenger,
       _media = media,
       _groups = groups,
       _self = self,
       _newId = newId,
       _clock = clock ?? DateTime.now;

  final Messenger _messenger;
  final CallMedia _media;
  final GroupService _groups;
  final AvId _self;
  final String Function() _newId;
  final DateTime Function() _clock;
  final Duration ringTimeout;

  /// Null when there is no call.
  final call = Store<CallState?>(null);
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _ringTimer;
  Timer? _clearTimer;

  /// Peers we sent an offer to and are waiting on an answer from.
  final _offered = <AvId>{};

  void init() {
    _subs
      // One signal at a time, in order: handlers await media work and
      // must never interleave.
      ..add(_messenger.incoming.listen((e) => _serially(() => _onIncoming(e))))
      ..add(_messenger.failures.listen(_onFailure))
      ..add(
        _media.candidates.listen((event) {
          final (peer, c) = event;
          final s = call.value;
          if (s == null) return;
          _signal(
            peer,
            s,
            CallAction.ice,
            candidate: c.candidate,
            sdpMid: c.sdpMid,
            sdpMLineIndex: c.sdpMLineIndex,
          );
        }),
      )
      ..add(_media.linkStates.listen((e) => _serially(() async => _onLink(e))));
  }

  Future<void> _queue = Future.value();

  void _serially(Future<void> Function() step) {
    _queue = _queue.then((_) => step()).catchError((Object _) {});
  }

  bool get busy {
    final s = call.value;
    return s != null && s.phase != CallPhase.ended;
  }

  Future<void> start(ConversationRef conversation) async {
    if (busy) return;
    final members = _membersOf(conversation);
    if (members.isEmpty) return;
    _clearTimer?.cancel();
    final state = CallState(
      callId: _newId(),
      conversation: conversation,
      inviter: _self,
      phase: CallPhase.calling,
    );
    call.value = state;
    if (!await _openMic()) return;
    for (final m in members) {
      _signal(m, state, CallAction.invite);
    }
    _ringTimer = Timer(ringTimeout, () {
      final s = call.value;
      if (s != null && s.phase == CallPhase.calling) {
        unawaited(_end(CallEndReason.noAnswer, notify: true));
      }
    });
  }

  Future<void> accept() async {
    final s = call.value;
    if (s == null || s.phase != CallPhase.incoming) return;
    _ringTimer?.cancel();
    call.value = s.copyWith(phase: CallPhase.connecting);
    if (!await _openMic()) {
      if (!s.isGroup) _signal(s.inviter, s, CallAction.decline);
      return;
    }
    // Everyone already in the call will send us an offer.
    for (final m in _membersOf(s.conversation)) {
      _signal(m, s, CallAction.accept);
    }
  }

  Future<void> decline() async {
    final s = call.value;
    if (s == null || s.phase != CallPhase.incoming) return;
    if (!s.isGroup) _signal(s.inviter, s, CallAction.decline);
    await _end(CallEndReason.declined, notify: false);
  }

  Future<void> hangUp() => _end(CallEndReason.hungUp, notify: true);

  void toggleMute() {
    final s = call.value;
    if (s == null) return;
    _media.setMuted(muted: !s.muted);
    call.value = s.copyWith(muted: !s.muted);
  }

  Future<void> toggleSpeaker() async {
    final s = call.value;
    if (s == null) return;
    await _media.setSpeaker(on: !s.speaker);
    call.value = s.copyWith(speaker: !s.speaker);
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _ringTimer?.cancel();
    _clearTimer?.cancel();
    await _media.closeAll();
  }

  // ── Signaling in ──────────────────────────────────────────────────

  Future<void> _onIncoming(Incoming event) async {
    final p = event.payload;
    if (p is! CallPayload) return;
    final from = event.from;
    final s = call.value;

    if (p.action == CallAction.invite) {
      await _onInvite(from, p);
      return;
    }
    if (s == null || s.callId != p.callId || s.phase == CallPhase.ended) {
      return;
    }
    if (!_membersOf(s.conversation).contains(from)) return;

    switch (p.action) {
      case CallAction.invite:
        break; // handled above
      case CallAction.ringing:
        call.value = s.copyWith(ringing: true);
      case CallAction.accept:
        if (s.phase == CallPhase.incoming) return; // we have not joined
        _ringTimer?.cancel();
        call.value = s.copyWith(
          joined: {...s.joined, from},
          phase: s.phase == CallPhase.calling ? CallPhase.connecting : null,
        );
        _offered.add(from);
        final sdp = await _media.createOffer(from);
        _signal(from, call.value!, CallAction.offer, sdp: sdp);
      case CallAction.offer:
        if (s.phase == CallPhase.incoming || p.sdp == null) return;
        if (_offered.contains(from)) {
          // Both offered at once: the larger AV-ID keeps its offer, the
          // other drops its own and answers.
          if (_self.value.compareTo(from.value) > 0) return;
          _offered.remove(from);
          await _media.closePeer(from);
        }
        final now = call.value!;
        call.value = now.copyWith(joined: {...now.joined, from});
        final answer = await _media.acceptOffer(from, p.sdp!);
        _signal(from, call.value!, CallAction.answer, sdp: answer);
      case CallAction.answer:
        if (p.sdp == null || !_offered.remove(from)) return;
        await _media.acceptAnswer(from, p.sdp!);
      case CallAction.ice:
        if (p.candidate == null) return;
        await _media.addCandidate(
          from,
          IceCandidate(p.candidate!, p.sdpMid, p.sdpMLineIndex),
        );
      case CallAction.decline:
        if (!s.isGroup) await _end(CallEndReason.declined, notify: false);
      case CallAction.busy:
        if (!s.isGroup) await _end(CallEndReason.busy, notify: false);
      case CallAction.hangup:
        await _peerLeft(from);
    }
  }

  Future<void> _onInvite(AvId from, CallPayload p) async {
    final conversation = p.groupId == null
        ? DirectRef(from)
        : GroupRef(p.groupId!);
    if (!_membersOf(conversation).contains(from)) return;
    if (busy) {
      if (call.value!.callId != p.callId) {
        _signalRaw(from, p.callId, p.groupId, CallAction.busy);
      }
      return;
    }
    _clearTimer?.cancel();
    final state = CallState(
      callId: p.callId,
      conversation: conversation,
      inviter: from,
      phase: CallPhase.incoming,
    );
    call.value = state;
    _signal(from, state, CallAction.ringing);
    _ringTimer = Timer(ringTimeout, () {
      if (call.value?.phase == CallPhase.incoming) {
        unawaited(_end(CallEndReason.noAnswer, notify: false));
      }
    });
  }

  void _onFailure(DeliveryFailure f) {
    final p = f.payload;
    final s = call.value;
    if (p is! CallPayload || s == null || p.callId != s.callId) return;
    if (p.action == CallAction.invite && !s.isGroup) {
      unawaited(_end(CallEndReason.unavailable, notify: false));
    }
  }

  void _onLink((AvId, LinkState) event) {
    final (peer, link) = event;
    final s = call.value;
    if (s == null || s.phase == CallPhase.ended) return;
    switch (link) {
      case LinkState.connected:
        call.value = s.copyWith(
          connected: {...s.connected, peer},
          phase: CallPhase.active,
          activeSince: s.activeSince ?? _clock(),
        );
      case LinkState.failed:
      case LinkState.closed:
        unawaited(_peerLeft(peer, failed: link == LinkState.failed));
      case LinkState.connecting:
        break;
    }
  }

  Future<void> _peerLeft(AvId peer, {bool failed = false}) async {
    if (call.value == null) return;
    _offered.remove(peer);
    await _media.closePeer(peer);
    final s = call.value;
    if (s == null) return;
    final connected = {...s.connected}..remove(peer);
    final joined = {...s.joined}..remove(peer);
    call.value = s.copyWith(connected: connected, joined: joined);
    final alone = connected.isEmpty && joined.isEmpty;
    if (!s.isGroup || (alone && s.phase != CallPhase.calling)) {
      await _end(
        failed ? CallEndReason.failed : CallEndReason.hungUp,
        notify: false,
      );
    }
  }

  /// False (and the call ends) if the microphone cannot be used.
  Future<bool> _openMic() async {
    try {
      await _media.openMicrophone();
      return true;
    } on Object {
      await _end(CallEndReason.failed, notify: false);
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<void> _end(CallEndReason reason, {required bool notify}) async {
    final s = call.value;
    if (s == null || s.phase == CallPhase.ended) return;
    _ringTimer?.cancel();
    if (notify) {
      for (final m in _membersOf(s.conversation)) {
        _signal(m, s, CallAction.hangup);
      }
    }
    _offered.clear();
    await _media.closeAll();
    call.value = s.copyWith(phase: CallPhase.ended, endReason: reason);
    // Keep "Call ended" on screen briefly, then clear.
    _clearTimer = Timer(const Duration(seconds: 2), () {
      if (call.value?.phase == CallPhase.ended) call.value = null;
    });
  }

  List<AvId> _membersOf(ConversationRef c) => switch (c) {
    DirectRef(:final peer) => [peer],
    GroupRef(:final groupId) => [
      for (final m in _groups.byId(groupId)?.members ?? const <Peer>[])
        if (m.id != _self) m.id,
    ],
  };

  void _signal(
    AvId to,
    CallState s,
    CallAction action, {
    String? sdp,
    String? candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) => _signalRaw(
    to,
    s.callId,
    s.conversation is GroupRef ? (s.conversation as GroupRef).groupId : null,
    action,
    sdp: sdp,
    candidate: candidate,
    sdpMid: sdpMid,
    sdpMLineIndex: sdpMLineIndex,
  );

  void _signalRaw(
    AvId to,
    String callId,
    String? groupId,
    CallAction action, {
    String? sdp,
    String? candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) => _messenger.send(
    to,
    CallPayload(
      callId: callId,
      action: action,
      groupId: groupId,
      sdp: sdp,
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    ),
  );
}
