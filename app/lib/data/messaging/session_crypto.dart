import 'dart:convert';

import 'package:av_protocol/av_protocol.dart';
import 'package:cryptography/cryptography.dart';

/// Keys for one conversation partner, valid for this app run only.
final class SessionKeys {
  const SessionKeys({
    required this.peerEphemeral,
    required this.sendKey,
    required this.receiveKey,
  });

  final List<int> peerEphemeral;
  final SecretKey sendKey;
  final SecretKey receiveKey;
}

/// The cryptographic primitives, kept apart from messaging logic.
///
/// - Key agreement: X25519 between this run's ephemeral key and the
///   peer's ephemeral key. Ephemeral keys never touch disk, so once the
///   app closes past messages cannot be decrypted (forward secrecy).
/// - Authentication: each ephemeral key is signed with the long-term
///   Ed25519 identity key.
/// - Encryption: XChaCha20-Poly1305 with a random 24-byte nonce and the
///   envelope routing fields as associated data.
final class SessionCrypto {
  SessionCrypto._(this._ephemeral, this.ephemeralPublic);

  static Future<SessionCrypto> create() async {
    final kp = await X25519().newKeyPair();
    final pub = (await kp.extractPublicKey()).bytes;
    return SessionCrypto._(kp, pub);
  }

  static final _x25519 = X25519();
  static final _ed25519 = Ed25519();
  static final _aead = Xchacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  final SimpleKeyPair _ephemeral;
  final List<int> ephemeralPublic;

  /// Bytes covered by a handshake signature.
  static List<int> handshakeTranscript({
    required String from,
    required String to,
    required List<int> ephemeral,
    required List<int>? peerEphemeral,
  }) => [
    ...utf8.encode('av-chat/handshake/v1|$from|$to|'),
    ...ephemeral,
    ...utf8.encode('|'),
    ...?peerEphemeral,
  ];

  static Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKey,
  }) => _ed25519.verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );

  Future<SessionKeys> derive({
    required AvId self,
    required AvId peer,
    required List<int> peerEphemeral,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _ephemeral,
      remotePublicKey: SimplePublicKey(
        peerEphemeral,
        type: KeyPairType.x25519,
      ),
    );
    final ids = [self.value, peer.value]..sort();
    final salt = utf8.encode(ids.join('|'));
    Future<SecretKey> key(AvId from, AvId to) => _hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode('av-chat/msg/v1|${from.value}>${to.value}'),
    );
    return SessionKeys(
      peerEphemeral: peerEphemeral,
      sendKey: await key(self, peer),
      receiveKey: await key(peer, self),
    );
  }

  /// Returns nonce ‖ ciphertext ‖ mac.
  static Future<List<int>> encrypt(
    List<int> plaintext,
    SecretKey key,
    List<int> aad,
  ) async {
    final box = await _aead.encrypt(
      plaintext,
      secretKey: key,
      nonce: _aead.newNonce(),
      aad: aad,
    );
    return box.concatenation();
  }

  /// Throws [SecretBoxAuthenticationError] if tampered or wrong key.
  static Future<List<int>> decrypt(
    List<int> sealed,
    SecretKey key,
    List<int> aad,
  ) {
    final box = SecretBox.fromConcatenation(
      sealed,
      nonceLength: _aead.nonceLength,
      macLength: _aead.macAlgorithm.macLength,
    );
    return _aead.decrypt(box, secretKey: key, aad: aad);
  }

  /// Associated data: binds ciphertext to its envelope's routing fields.
  static List<int> aadFor(Envelope e) =>
      utf8.encode('${e.id}|${e.from}|${e.to}|${e.type.name}');
}
