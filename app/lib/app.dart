import 'package:av_chat/di/providers.dart';
import 'package:av_chat/presentation/features/call/call_overlay.dart';
import 'package:av_chat/presentation/features/home/background_coordinator.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AvChatApp extends ConsumerStatefulWidget {
  const AvChatApp({super.key});

  @override
  ConsumerState<AvChatApp> createState() => _AvChatAppState();
}

class _AvChatAppState extends ConsumerState<AvChatApp> {
  static const _autoLock = Duration(seconds: 30);
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final hiddenAt = _hiddenAt;
        _hiddenAt = null;
        if (hiddenAt == null) return;
        final hasIdentity = ref.read(identityProvider).value != null;
        if (hasIdentity && DateTime.now().difference(hiddenAt) > _autoLock) {
          ref.read(lockedProvider.notifier).lock();
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSandbox = ref.watch(appEnvironmentProvider).isSandbox;
    // Start the session as soon as there is an identity.
    ref.watch(sessionProvider);
    return MaterialApp.router(
      title: 'AV Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        final app = Stack(
          children: [
            ?child,
            // Own Overlay so tooltips and ink work above the navigator.
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => const CallOverlay()),
                ],
              ),
            ),
          ],
        );
        final dark = Theme.of(context).brightness == Brightness.dark;
        final coordinated = AnnotatedRegion<SystemUiOverlayStyle>(
          // Transparent system bars that match the theme on every screen.
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
          child: BackgroundCoordinator(child: app),
        );
        return isSandbox
            ? Banner(
                message: 'SANDBOX',
                location: BannerLocation.topEnd,
                child: coordinated,
              )
            : coordinated;
      },
    );
  }
}
