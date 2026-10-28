import 'dart:convert';
import 'dart:math';

import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/repositories/identity_repository.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:cryptography/cryptography.dart';

/// Ed25519 identity. The 32-byte seed is the only secret that is kept.
final class SecureIdentityRepository implements IdentityRepository {
  SecureIdentityRepository(this._store);

  static const _seedKey = 'identity.seed';
  static const _nameKey = 'identity.name';

  final KeyValueStore _store;
  final _ed25519 = Ed25519();
  SimpleKeyPair? _keyPair;
  Identity? _identity;

  @override
  Future<Identity?> load() async {
    if (_identity != null) return _identity;
    final seed = await _store.read(_seedKey);
    final name = await _store.read(_nameKey);
    if (seed == null || name == null) return null;
    return _identity = await _fromSeed(base64Decode(seed), name);
  }

  @override
  Future<Identity> create(String name) async {
    final seed = List<int>.generate(32, (_) => _random.nextInt(256));
    await _store.write(_seedKey, base64Encode(seed));
    await _store.write(_nameKey, name.trim());
    return _identity = await _fromSeed(seed, name.trim());
  }

  @override
  Future<Identity> rename(String name) async {
    final current = await load();
    if (current == null) throw StateError('No identity yet');
    await _store.write(_nameKey, name.trim());
    return _identity = current.copyWith(name: name.trim());
  }

  @override
  Future<List<int>> sign(List<int> data) async {
    final kp = _keyPair;
    if (kp == null) throw StateError('Identity not loaded');
    return (await _ed25519.sign(data, keyPair: kp)).bytes;
  }

  Future<Identity> _fromSeed(List<int> seed, String name) async {
    final kp = await _ed25519.newKeyPairFromSeed(seed);
    _keyPair = kp;
    final pub = (await kp.extractPublicKey()).bytes;
    return Identity(id: AvId.fromPublicKey(pub), name: name, publicKey: pub);
  }

  static final Random _random = SecureRandom.defaultRandom;
}
