import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/payloads/wire_payload.dart';
import 'package:av_chat/domain/repositories/group_repository.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/domain/user_facing_exception.dart';
import 'package:av_protocol/av_protocol.dart';

/// Groups of up to [Group.maxMembers]. The owner is the source of truth:
/// every change is broadcast by the owner as a full [GroupUpdatePayload].
final class GroupService {
  GroupService(this._repository, this._messenger, this._self, this._newId);

  final GroupRepository _repository;
  final Messenger _messenger;
  final Identity _self;
  final String Function() _newId;
  final groups = Store<List<Group>>(const []);
  StreamSubscription<Incoming>? _sub;

  Peer get _me =>
      Peer(id: _self.id, name: _self.name, publicKey: _self.publicKey);

  Future<void> init() async {
    groups.value = await _repository.load();
    _sub = _messenger.incoming.listen(_onIncoming);
  }

  Group? byId(String id) {
    for (final g in groups.value) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Any group member we may talk to (for handshake trust).
  Peer? memberById(AvId id) {
    for (final g in groups.value) {
      for (final m in g.members) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  Future<Group> create(String name, List<Peer> members) async {
    final others = [
      for (final m in members)
        if (m.id != _self.id) m,
    ];
    _checkSize(others.length + 1);
    if (others.any((m) => m.publicKey == null)) {
      throw const UserFacingException(
        'Wait until every member has accepted you',
      );
    }
    final group = Group(
      id: _newId(),
      name: name.trim(),
      owner: _self.id,
      members: [_me, ...others],
    );
    await _save(group);
    _broadcast(group, group.members);
    return group;
  }

  Future<void> addMembers(String groupId, List<Peer> newMembers) async {
    final group = _ownedGroup(groupId);
    final merged = [
      ...group.members,
      for (final m in newMembers)
        if (!group.contains(m.id) && m.publicKey != null) m,
    ];
    _checkSize(merged.length);
    final updated = group.copyWith(members: merged);
    await _save(updated);
    _broadcast(updated, updated.members);
  }

  Future<void> removeMember(String groupId, AvId member) async {
    final group = _ownedGroup(groupId);
    if (member == _self.id) return leave(groupId);
    final updated = group.copyWith(
      members: [
        for (final m in group.members)
          if (m.id != member) m,
      ],
    );
    await _save(updated);
    // The removed member gets the update too, so they drop the group.
    _broadcast(updated, group.members);
  }

  Future<void> rename(String groupId, String name) async {
    final updated = _ownedGroup(groupId).copyWith(name: name.trim());
    await _save(updated);
    _broadcast(updated, updated.members);
  }

  Future<void> leave(String groupId) async {
    final group = byId(groupId);
    if (group == null) return;
    final remaining = [
      for (final m in group.members)
        if (m.id != _self.id) m,
    ];
    if (group.owner == _self.id && remaining.isNotEmpty) {
      // Hand ownership to the next member, then go.
      final handedOver = Group(
        id: group.id,
        name: group.name,
        owner: remaining.first.id,
        members: remaining,
      );
      _broadcast(handedOver, remaining);
    } else {
      for (final m in remaining) {
        _messenger.send(m.id, GroupLeavePayload(group.id));
      }
    }
    await _delete(groupId);
  }

  Future<void> dispose() async => _sub?.cancel();

  Future<void> _onIncoming(Incoming event) async {
    switch (event.payload) {
      case GroupUpdatePayload(:final group):
        await _onUpdate(event.from, group);
      case GroupLeavePayload(:final groupId):
        await _onLeave(event.from, groupId);
      default:
        return;
    }
  }

  Future<void> _onUpdate(AvId from, Group incoming) async {
    final existing = byId(incoming.id);
    // Only the current owner may change a group.
    final authority = existing?.owner ?? incoming.owner;
    if (from != authority) return;
    if (incoming.members.length > Group.maxMembers) return;
    if (!incoming.contains(_self.id)) {
      await _delete(incoming.id);
      return;
    }
    await _save(incoming);
  }

  Future<void> _onLeave(AvId from, String groupId) async {
    final group = byId(groupId);
    if (group == null || !group.contains(from)) return;
    final updated = group.copyWith(
      members: [
        for (final m in group.members)
          if (m.id != from) m,
      ],
    );
    await _save(updated);
    if (group.owner == _self.id) _broadcast(updated, updated.members);
  }

  Group _ownedGroup(String groupId) {
    final group = byId(groupId);
    if (group == null) throw StateError('Group not found');
    if (group.owner != _self.id) {
      throw StateError('Only the group owner can do that');
    }
    return group;
  }

  void _checkSize(int count) {
    if (count > Group.maxMembers) {
      throw const UserFacingException(
        'A group can have at most ${Group.maxMembers} people',
      );
    }
    if (count < 2) {
      throw const UserFacingException('Pick at least one member');
    }
  }

  void _broadcast(Group group, List<Peer> to) {
    for (final m in to) {
      if (m.id != _self.id) _messenger.send(m.id, GroupUpdatePayload(group));
    }
  }

  Future<void> _save(Group group) async {
    groups.value = [
      for (final g in groups.value)
        if (g.id != group.id) g,
      group,
    ];
    await _repository.saveAll(groups.value);
  }

  Future<void> _delete(String groupId) async {
    groups.value = [
      for (final g in groups.value)
        if (g.id != groupId) g,
    ];
    await _repository.saveAll(groups.value);
  }
}
