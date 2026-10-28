import 'package:cryptography/cryptography.dart';

abstract interface class SignatureVerifier {
  Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKey,
  });
}

final class Ed25519Verifier implements SignatureVerifier {
  final _algorithm = Ed25519();

  @override
  Future<bool> verify({
    required List<int> message,
    required List<int> signature,
    required List<int> publicKey,
  }) {
    return _algorithm.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }
}
