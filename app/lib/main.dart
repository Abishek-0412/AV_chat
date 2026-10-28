import 'package:av_chat/app.dart';
import 'package:av_chat/data/platform/android_system_alerts.dart';
import 'package:av_chat/di/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final alerts = AndroidSystemAlerts();
  await alerts.init();
  runApp(
    ProviderScope(
      overrides: [systemAlertsProvider.overrideWithValue(alerts)],
      child: const AvChatApp(),
    ),
  );
}
