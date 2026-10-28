import 'package:av_chat/app.dart';
import 'package:av_chat/core/config/app_environment.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_identity_repository.dart';
import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/services/app_lock.dart';
import 'package:av_chat/domain/services/system_alerts.dart';
import 'package:av_chat/sandbox/fake_call_media.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeLock implements AppLock {
  String? pin;
  @override
  Future<bool> hasPin() async => pin != null;
  @override
  Future<void> setPin(String p) async => pin = p;
  @override
  Future<bool> verifyPin(String p) async => p == pin;
  @override
  Future<bool> biometricsAvailable() async => false;
  @override
  Future<bool> biometricsEnabled() async => false;
  @override
  Future<void> setBiometricsEnabled({required bool enabled}) async {}
  @override
  Future<bool> authenticateWithBiometrics() async => false;
}

Widget _app(KeyValueStore store, FakeLock lock, {bool sandbox = false}) {
  final net = InMemoryRelayNetwork();
  final media = FakeMediaNetwork();
  return ProviderScope(
    overrides: [
      appEnvironmentProvider.overrideWithValue(
        AppEnvironment(relayUrl: 'ws://test:8080', isSandbox: sandbox),
      ),
      keyValueStoreProvider.overrideWithValue(store),
      systemAlertsProvider.overrideWithValue(const NoSystemAlerts()),
      appLockProvider.overrideWithValue(lock),
      relayFactoryProvider.overrideWithValue(
        (self, _) => net.client(self.id.value),
      ),
      callMediaFactoryProvider.overrideWithValue(
        () => media.forUser(AvId.parse('AV-AAAA-AAAA-AAAA')),
      ),
    ],
    child: const AvChatApp(),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // Crypto runs on real futures; give it real time, then settle frames.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first launch shows onboarding', (tester) async {
    await tester.pumpWidget(_app(MemoryKeyValueStore(), FakeLock()));
    await _settle(tester);
    expect(find.text('Private by design'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);
  });

  testWidgets('existing identity starts locked; right PIN opens chats', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await tester.runAsync(
      () => SecureIdentityRepository(store).create('Alice'),
    );
    final lock = FakeLock()..pin = '123456';
    await tester.pumpWidget(_app(store, lock));
    await _settle(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);

    for (final d in '111111'.split('')) {
      await tester.tap(find.text(d).last);
    }
    await _settle(tester);
    expect(find.textContaining('Wrong PIN'), findsOneWidget);

    for (final d in '123456'.split('')) {
      await tester.tap(find.text(d).last);
    }
    await _settle(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('sandbox build shows a SANDBOX banner', (tester) async {
    await tester.pumpWidget(
      _app(MemoryKeyValueStore(), FakeLock(), sandbox: true),
    );
    await _settle(tester);
    expect(find.byType(Banner), findsOneWidget);
  });
}
