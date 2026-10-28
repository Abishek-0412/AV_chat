import 'package:av_chat/core/config/app_environment.dart';
import 'package:av_chat/data/calls/webrtc_call_media.dart';
import 'package:av_chat/data/messaging/secure_messenger.dart';
import 'package:av_chat/data/platform/android_system_alerts.dart';
import 'package:av_chat/data/platform/media_capture.dart';
import 'package:av_chat/data/platform/pin_app_lock.dart';
import 'package:av_chat/data/relay/websocket_relay_client.dart';
import 'package:av_chat/data/secure/key_value_store.dart';
import 'package:av_chat/data/secure/secure_identity_repository.dart';
import 'package:av_chat/data/secure/secure_settings_repository.dart';
import 'package:av_chat/di/app_session.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/identity.dart';
import 'package:av_chat/domain/repositories/identity_repository.dart';
import 'package:av_chat/domain/repositories/settings_repository.dart';
import 'package:av_chat/domain/services/app_lock.dart';
import 'package:av_chat/domain/services/call_media.dart';
import 'package:av_chat/domain/services/call_service.dart';
import 'package:av_chat/domain/services/chat_service.dart';
import 'package:av_chat/domain/services/relay_client.dart';
import 'package:av_chat/domain/services/system_alerts.dart';
import 'package:av_chat/domain/value_objects/connection_status.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Composition root. Sandbox and tests override these. ──────────────

final appEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => AppEnvironment.fromDefines(),
);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => const SecureKeyValueStore(),
);

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => SecureIdentityRepository(ref.watch(keyValueStoreProvider)),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SecureSettingsRepository(ref.watch(keyValueStoreProvider)),
);

final appLockProvider = Provider<AppLock>(
  (ref) => PinAppLock(ref.watch(keyValueStoreProvider)),
);

typedef RelayFactory = RelayClient Function(Identity self, Signer sign);

final relayFactoryProvider = Provider<RelayFactory>(
  (ref) =>
      (self, sign) => WebSocketRelayClient(self: self, sign: sign),
);

final callMediaFactoryProvider = Provider<CallMedia Function()>(
  (ref) => WebRtcCallMedia.new,
);

final mediaCaptureProvider = Provider<MediaCapture>((ref) {
  final media = MediaCapture();
  ref.onDispose(media.dispose);
  return media;
});

/// Initialised in main() before the app starts.
final systemAlertsProvider = Provider<SystemAlerts>(
  (ref) => AndroidSystemAlerts(),
);

// ── Identity ─────────────────────────────────────────────────────────

final identityProvider = AsyncNotifierProvider<IdentityNotifier, Identity?>(
  IdentityNotifier.new,
);

class IdentityNotifier extends AsyncNotifier<Identity?> {
  IdentityRepository get _repo => ref.read(identityRepositoryProvider);

  @override
  Future<Identity?> build() => _repo.load();

  Future<Identity> create(String name) async {
    final identity = await _repo.create(name);
    state = AsyncData(identity);
    return identity;
  }

  Future<void> rename(String name) async {
    if (name.trim().isEmpty) return;
    final identity = await _repo.rename(name);
    state = AsyncData(identity);
    ref.read(sessionProvider).value?.rename(identity.name);
  }
}

/// Changes only when the identity itself changes, not on rename.
final _identityIdProvider = Provider<AvId?>(
  (ref) => ref.watch(identityProvider).value?.id,
);

// ── Relay address ────────────────────────────────────────────────────

final relayUrlProvider = AsyncNotifierProvider<RelayUrlNotifier, String>(
  RelayUrlNotifier.new,
);

class RelayUrlNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() async =>
      await ref.read(settingsRepositoryProvider).relayUrl() ??
      ref.read(appEnvironmentProvider).relayUrl;

  /// Empty resets to the build default. Reconnects without losing chats.
  Future<void> set(String url) async {
    await ref.read(settingsRepositoryProvider).setRelayUrl(url);
    ref.invalidateSelf();
    final next = await future;
    await ref.read(sessionProvider).value?.relay.connect(next);
  }
}

// ── Lock ─────────────────────────────────────────────────────────────

/// True while the lock screen must be shown.
final lockedProvider = NotifierProvider<LockedNotifier, bool>(
  LockedNotifier.new,
);

class LockedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void lock() => state = true;
  void unlock() => state = false;
}

// ── Running session ──────────────────────────────────────────────────

final sessionProvider = FutureProvider<AppSession?>((ref) async {
  final id = ref.watch(_identityIdProvider);
  if (id == null) return null;
  final identity = ref.read(identityProvider).requireValue!;
  final identities = ref.read(identityRepositoryProvider);
  final session = await AppSession.start(
    identity: identity,
    identities: identities,
    store: ref.read(keyValueStoreProvider),
    relay: ref.read(relayFactoryProvider)(identity, identities.sign),
    relayUrl: await ref.read(relayUrlProvider.future),
    callMedia: ref.read(callMediaFactoryProvider)(),
  );
  ref.onDispose(session.dispose);
  return session;
});

Stream<T> _fromSession<T>(
  Ref ref,
  T empty,
  Stream<T> Function(AppSession s) pick,
) {
  final session = ref.watch(sessionProvider).value;
  return session == null ? Stream.value(empty) : pick(session);
}

final connectionStatusProvider = StreamProvider<ConnectionStatus>(
  (ref) => _fromSession(ref, ConnectionStatus.offline, (s) => s.relay.status),
);

final contactsProvider = StreamProvider<List<Contact>>(
  (ref) => _fromSession(ref, const [], (s) => s.contacts.contacts.stream),
);

final contactRequestsProvider = StreamProvider<List<ContactRequest>>(
  (ref) => _fromSession(ref, const [], (s) => s.contacts.requests.stream),
);

final groupsProvider = StreamProvider<List<Group>>(
  (ref) => _fromSession(ref, const [], (s) => s.groups.groups.stream),
);

final conversationsProvider = StreamProvider<Map<String, Conversation>>(
  (ref) => _fromSession(ref, const {}, (s) => s.chats.conversations.stream),
);

final onlineProvider = StreamProvider<Set<AvId>>(
  (ref) => _fromSession(ref, const {}, (s) => s.presence.online.stream),
);

final callProvider = StreamProvider<CallState?>(
  (ref) => _fromSession(ref, null, (s) => s.calls.call.stream),
);
