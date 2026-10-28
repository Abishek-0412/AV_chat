abstract interface class SettingsRepository {
  /// User-entered relay address; null means use the build default.
  Future<String?> relayUrl();
  Future<void> setRelayUrl(String? url);
}
