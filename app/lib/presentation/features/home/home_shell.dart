import 'package:av_chat/di/providers.dart';
import 'package:av_chat/presentation/shared/widgets/connection_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Bottom navigation around the three main tabs.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = (ref.watch(conversationsProvider).value ?? const {}).values
        .fold<int>(0, (sum, c) => sum + c.unread);
    final requests = ref.watch(contactRequestsProvider).value?.length ?? 0;
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: shell),
          const ConnectionBanner(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble),
            ),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: requests > 0,
              label: Text('$requests'),
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: requests > 0,
              label: Text('$requests'),
              child: const Icon(Icons.people),
            ),
            label: 'Contacts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
