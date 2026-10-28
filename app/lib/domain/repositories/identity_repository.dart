import 'package:av_chat/domain/entities/identity.dart';

abstract interface class IdentityRepository {
  Future<Identity?> load();

  /// Generates a new key pair. Replaces any existing identity.
  Future<Identity> create(String name);

  Future<Identity> rename(String name);

  /// Ed25519 signature with the identity private key.
  Future<List<int>> sign(List<int> data);
}
