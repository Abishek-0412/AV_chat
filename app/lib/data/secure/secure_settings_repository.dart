import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/domain/repositories/settings_repository.dart';

final class SecureSettingsRepository implements SettingsRepository {
  SecureSettingsRepository(this._store);
  static const _relayKey = 'settings.relayUrl';
  final KeyValueStore _store;

  @override
  Future<String?> relayUrl() => _store.read(_relayKey);

  @override
  Future<void> setRelayUrl(String? url) => url == null || url.trim().isEmpty
      ? _store.delete(_relayKey)
      : _store.write(_relayKey, url.trim());
}
