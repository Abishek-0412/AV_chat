import 'dart:convert';

import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/repositories/contact_repository.dart';

final class SecureContactRepository implements ContactRepository {
  SecureContactRepository(this._store);
  static const _key = 'contacts';
  final KeyValueStore _store;

  @override
  Future<List<Contact>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        Contact.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> saveAll(List<Contact> contacts) => _store.write(
    _key,
    jsonEncode([for (final c in contacts) c.toJson()]),
  );
}
