import 'package:av_chat/app.dart';
import 'package:av_chat/core/config/app_environment.dart';
import 'package:av_chat/data/platform/pin_app_lock.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/services/system_alerts.dart';
import 'package:av_chat/sandbox/fake_call_media.dart';
import 'package:av_chat/sandbox/in_memory_relay.dart';
import 'package:av_chat/sandbox/sandbox_bot.dart';
import 'package:av_chat/sandbox/sandbox_seeder.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whole app on one phone, no server: an in-memory relay with demo bots.
/// Nothing is stored (fresh onboarding each launch).
/// `flutter run -t lib/main_sandbox.dart`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Allow screenshots in the sandbox build only, for demos and design QA.
  await const MethodChannel('av_chat/window').invokeMethod('setSecure', false);

  final net = InMemoryRelayNetwork();
  final calls = FakeMediaNetwork();
  final echo = await SandboxBot.start(
    net,
    name: 'Echo',
    reply: (t) => 'You said: "$t"',
  );
  final mia = await SandboxBot.start(
    net,
    name: 'Mia',
    reply: (t) => t.length < 12 ? 'Haha 😄' : 'Sounds good to me!',
  );
  final sam = await SandboxBot.start(
    net,
    name: 'Sam',
    reply: (_) => '',
    online: false,
  );
  SandboxBot.register([echo, mia, sam]);
  echo.trust(mia);
  mia.trust(echo);

  final store = MemoryKeyValueStore();
  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            relayUrl: 'sandbox://in-memory',
            isSandbox: true,
          ),
        ),
        keyValueStoreProvider.overrideWithValue(store),
        appLockProvider.overrideWithValue(PinAppLock(store)),
        relayFactoryProvider.overrideWithValue(
          (self, _) => net.client(self.id.value),
        ),
        callMediaFactoryProvider.overrideWithValue(
          () => calls.forUser(AvId.parse('AV-SAND-BOXA-AAAA')),
        ),
        systemAlertsProvider.overrideWithValue(const NoSystemAlerts()),
      ],
      child: SandboxSeeder(
        bots: [echo, mia, sam],
        groupWith: [echo, mia],
        child: const AvChatApp(),
      ),
    ),
  );
}
