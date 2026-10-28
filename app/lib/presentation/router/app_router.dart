import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/presentation/features/chat/chat_screen.dart';
import 'package:av_chat/presentation/features/chats/chats_screen.dart';
import 'package:av_chat/presentation/features/contacts/add_contact_screen.dart';
import 'package:av_chat/presentation/features/contacts/contact_info_screen.dart';
import 'package:av_chat/presentation/features/contacts/contacts_screen.dart';
import 'package:av_chat/presentation/features/groups/group_info_screen.dart';
import 'package:av_chat/presentation/features/groups/new_group_screen.dart';
import 'package:av_chat/presentation/features/home/home_shell.dart';
import 'package:av_chat/presentation/features/lock/lock_screen.dart';
import 'package:av_chat/presentation/features/onboarding/onboarding_screen.dart';
import 'package:av_chat/presentation/features/settings/settings_screen.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const lock = '/lock';
  static const chats = '/chats';
  static const contacts = '/contacts';
  static const settings = '/settings';
  static const addContact = '/contacts/add';
  static const newGroup = '/groups/new';

  static String chat(ConversationRef ref) => '/chat/${ref.key}';
  static String contact(AvId id) => '/contact/${id.value}';
  static String group(String id) => '/group/$id';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever identity or lock state changes.
  final refresh = ValueNotifier(0);
  ref
    ..listen(identityProvider, (_, _) => refresh.value++)
    ..listen(lockedProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final identity = ref.read(identityProvider);
      final locked = ref.read(lockedProvider);
      final at = state.matchedLocation;
      if (identity.isLoading) {
        return at == AppRoutes.splash ? null : AppRoutes.splash;
      }
      if (identity.value == null) {
        return at == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }
      if (at == AppRoutes.onboarding) return null; // finishing up
      if (locked) return at == AppRoutes.lock ? null : AppRoutes.lock;
      if (at == AppRoutes.lock || at == AppRoutes.splash) {
        return AppRoutes.chats;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(path: AppRoutes.lock, builder: (_, _) => const LockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chats,
                builder: (_, _) => const ChatsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.contacts,
                builder: (_, _) => const ContactsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.addContact,
        builder: (_, _) => const AddContactScreen(),
      ),
      GoRoute(
        path: AppRoutes.newGroup,
        builder: (_, _) => const NewGroupScreen(),
      ),
      GoRoute(
        path: '/chat/:key',
        builder: (_, state) => ChatScreen(
          conversation: ConversationRef.parse(state.pathParameters['key']!),
        ),
      ),
      GoRoute(
        path: '/contact/:id',
        builder: (_, state) =>
            ContactInfoScreen(id: AvId.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/group/:id',
        builder: (_, state) =>
            GroupInfoScreen(groupId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
