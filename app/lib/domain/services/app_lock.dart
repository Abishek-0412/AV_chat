abstract interface class AppLock {
  Future<bool> hasPin();
  Future<void> setPin(String pin);
  Future<bool> verifyPin(String pin);

  Future<bool> biometricsAvailable();
  Future<bool> biometricsEnabled();
  Future<void> setBiometricsEnabled({required bool enabled});

  /// Shows the system fingerprint prompt.
  Future<bool> authenticateWithBiometrics();
}
