import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/contact.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Best known name for an AV-ID: contact name, else group member name,
/// else the AV-ID itself.
String nameOf(WidgetRef ref, AvId id) {
  final self = ref.watch(identityProvider).value;
  if (self?.id == id) return 'You';
  for (final c in ref.watch(contactsProvider).value ?? const <Contact>[]) {
    if (c.id == id) return c.name;
  }
  for (final g in ref.watch(groupsProvider).value ?? const <Group>[]) {
    for (final m in g.members) {
      if (m.id == id) return m.name;
    }
  }
  return id.value;
}

String titleOf(WidgetRef ref, ConversationRef conversation) =>
    switch (conversation) {
      DirectRef(:final peer) => nameOf(ref, peer),
      GroupRef(:final groupId) =>
        ref
                .watch(groupsProvider)
                .value
                ?.where((g) => g.id == groupId)
                .firstOrNull
                ?.name ??
            'Group',
    };
