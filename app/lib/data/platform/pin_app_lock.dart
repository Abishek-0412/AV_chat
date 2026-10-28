import 'dart:convert';

import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/domain/services/app_lock.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// PIN (stored only as a salted PBKDF2 hash) plus optional fingerprint.
final class PinAppLock implements AppLock {
  PinAppLock(this._store, {LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  static const _hashKey = 'lock.pinHash';
  static const _saltKey = 'lock.pinSalt';
  static const _bioKey = 'lock.biometrics';

  final KeyValueStore _store;
  final LocalAuthentication _auth;
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 60000,
    bits: 256,
  );

  @override
  Future<bool> hasPin() async => await _store.read(_hashKey) != null;

  @override
  Future<void> setPin(String pin) async {
    final salt = List<int>.generate(
      16,
      (_) => SecureRandom.defaultRandom.nextInt(256),
    );
    await _store.write(_saltKey, base64Encode(salt));
    await _store.write(_hashKey, base64Encode(await _hash(pin, salt)));
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final salt = await _store.read(_saltKey);
    final hash = await _store.read(_hashKey);
    if (salt == null || hash == null) return false;
    final actual = await _hash(pin, base64Decode(salt));
    return _constantTimeEquals(actual, base64Decode(hash));
  }

  @override
  Future<bool> biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> biometricsEnabled() async =>
      await _store.read(_bioKey) == 'true';

  @override
  Future<void> setBiometricsEnabled({required bool enabled}) =>
      _store.write(_bioKey, '$enabled');

  @override
  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock AV Chat',
        biometricOnly: true,
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }

  Future<List<int>> _hash(String pin, List<int> salt) async {
    final key = await _kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
