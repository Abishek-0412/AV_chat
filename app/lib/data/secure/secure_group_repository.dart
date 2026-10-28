import 'dart:convert';

import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/repositories/group_repository.dart';

final class SecureGroupRepository implements GroupRepository {
  SecureGroupRepository(this._store);
  static const _key = 'groups';
  final KeyValueStore _store;

  @override
  Future<List<Group>> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        Group.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> saveAll(List<Group> groups) => _store.write(
    _key,
    jsonEncode([for (final g in groups) g.toJson()]),
  );
}
