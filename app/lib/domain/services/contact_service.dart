import 'dart:async';

import 'package:av_chat/core/state/store.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/contact_card.dart';
import 'package:av_chat/domain/repositories/contact_repository.dart';
import 'package:av_chat/domain/services/messenger.dart';
import 'package:av_chat/domain/user_facing_exception.dart';
import 'package:av_protocol/av_protocol.dart';

/// Contacts (kept, encrypted) and incoming requests (memory only).
final class ContactService {
  ContactService(this._repository, this._messenger, this._self);

  final ContactRepository _repository;
  final Messenger _messenger;
  final AvId _self;
  final contacts = Store<List<Contact>>(const []);
  final requests = Store<List<ContactRequest>>(const []);
  final _subs = <StreamSubscription<Object?>>[];

  Future<void> init() async {
    contacts.value = await _repository.load();
    _subs
      ..add(_messenger.requests.listen(_onRequest))
      ..add(_messenger.keysLearned.listen(_onKeyLearned));
  }

  Contact? byId(AvId id) {
    for (final c in contacts.value) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// From a scanned QR code: key is known and verified by its hash.
  Future<void> addFromCard(ContactCard card) async {
    _checkNotSelf(card.id);
    await _upsert(
      Contact(id: card.id, name: card.name, publicKey: card.publicKey),
    );
    _messenger.introduce(card.id);
  }

  /// From a typed AV-ID: pending until they answer with their key.
  Future<void> addById(AvId id, {String? name}) async {
    _checkNotSelf(id);
    final existing = byId(id);
    if (existing == null) {
      final label = (name?.trim().isNotEmpty ?? false)
          ? name!.trim()
          : id.value;
      await _upsert(Contact(id: id, name: label));
    }
    _messenger.introduce(id);
  }

  Future<void> accept(ContactRequest request) async {
    await _upsert(
      Contact(
        id: request.id,
        name: request.name,
        publicKey: request.publicKey,
      ),
    );
    _dropRequest(request.id);
    _messenger.accept(request.id);
  }

  void decline(AvId id) {
    _dropRequest(id);
    _messenger.forget(id);
  }

  Future<void> remove(AvId id) async {
    contacts.value = [
      for (final c in contacts.value)
        if (c.id != id) c,
    ];
    await _repository.saveAll(contacts.value);
  }

  Future<void> rename(AvId id, String name) async {
    final c = byId(id);
    if (c == null || name.trim().isEmpty) return;
    await _upsert(c.copyWith(name: name.trim()));
  }

  Future<void> setVerified(AvId id, {required bool verified}) async {
    final c = byId(id);
    if (c == null) return;
    await _upsert(c.copyWith(verified: verified));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }

  void _checkNotSelf(AvId id) {
    if (id == _self) throw const UserFacingException('That is your own AV-ID');
  }

  void _onRequest(ContactRequest request) {
    if (byId(request.id) != null) return;
    requests.value = [
      for (final r in requests.value)
        if (r.id != request.id) r,
      request,
    ];
  }

  Future<void> _onKeyLearned(KeyLearned learned) async {
    final c = byId(learned.id);
    if (c == null || !c.isPending) return;
    final keepName = c.name != c.id.value;
    await _upsert(
      c.copyWith(
        publicKey: learned.publicKey,
        name: keepName ? c.name : learned.name,
      ),
    );
  }

  void _dropRequest(AvId id) {
    requests.value = [
      for (final r in requests.value)
        if (r.id != id) r,
    ];
  }

  Future<void> _upsert(Contact contact) async {
    final list = [
      for (final c in contacts.value)
        if (c.id != contact.id) c,
      contact,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    contacts.value = list;
    await _repository.saveAll(list);
  }
}
