/// Build-time settings. Override with `--dart-define`, e.g.
/// `flutter run --dart-define=RELAY_URL=ws://192.168.1.5:8080`.
final class AppEnvironment {
  const AppEnvironment({required this.relayUrl, this.isSandbox = false});

  /// Default points at the host PC from the Android emulator.
  factory AppEnvironment.fromDefines() => const AppEnvironment(
    relayUrl: String.fromEnvironment(
      'RELAY_URL',
      defaultValue: 'ws://10.0.2.2:8080',
    ),
  );

  final String relayUrl;

  /// True when running `main_sandbox.dart` with fake services.
  final bool isSandbox;
}
