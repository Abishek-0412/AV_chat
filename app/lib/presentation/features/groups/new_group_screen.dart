import 'package:av_chat/di/providers.dart';
import 'package:av_chat/domain/entities/conversation_ref.dart';
import 'package:av_chat/domain/entities/group.dart';
import 'package:av_chat/domain/entities/peer.dart';
import 'package:av_chat/domain/user_facing_exception.dart';
import 'package:av_chat/presentation/router/app_router.dart';
import 'package:av_chat/presentation/shared/theme/app_spacing.dart';
import 'package:av_chat/presentation/shared/widgets/av_avatar.dart';
import 'package:av_protocol/av_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Name + pick up to 9 contacts (you make 10).
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _name = TextEditingController();
  final _picked = <AvId>{};
  var _busy = false;

  static const int _maxOthers = Group.maxMembers - 1;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    setState(() => _busy = true);
    final contacts = ref.read(contactsProvider).value ?? const [];
    try {
      final group = await session.groups.create(_name.text, [
        for (final c in contacts)
          if (_picked.contains(c.id)) c.asPeer,
      ]);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.chat(GroupRef(group.id)));
    } on UserFacingException catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = (ref.watch(contactsProvider).value ?? const [])
        .where((c) => !c.isPending)
        .toList();
    final online = ref.watch(onlineProvider).value ?? const {};
    final ready = _name.text.trim().isNotEmpty && _picked.isNotEmpty && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      floatingActionButton: AnimatedScale(
        scale: ready ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: FloatingActionButton.extended(
          onPressed: ready ? _create : null,
          icon: const Icon(Icons.check),
          label: const Text('Create'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Group name',
                prefixIcon: Icon(Icons.groups_2_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Members ${_picked.length}/$_maxOthers',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final c in contacts)
            CheckboxListTile(
              value: _picked.contains(c.id),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  if (_picked.length < _maxOthers) _picked.add(c.id);
                } else {
                  _picked.remove(c.id);
                }
              }),
              secondary: AvAvatar(
                seed: DirectRef(c.id).key,
                name: c.name,
                online: online.contains(c.id),
              ),
              title: Text(c.name),
              subtitle: Text(online.contains(c.id) ? 'Online' : 'Offline'),
            ),
          if (contacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Members who are offline get the group the next time you '
                'make a change while they are online.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Member picker, reused by the group info screen to add people.
Future<List<Peer>?> pickMembers(
  BuildContext context,
  WidgetRef ref, {
  required Set<AvId> exclude,
  required int max,
}) {
  final contacts = (ref.read(contactsProvider).value ?? const [])
      .where((c) => !c.isPending && !exclude.contains(c.id))
      .toList();
  final picked = <AvId>{};
  return showModalBottomSheet<List<Peer>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Add members (${picked.length}/$max)',
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            if (contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('All your contacts are already in this group.'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in contacts)
                    CheckboxListTile(
                      value: picked.contains(c.id),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          if (picked.length < max) picked.add(c.id);
                        } else {
                          picked.remove(c.id);
                        }
                      }),
                      title: Text(c.name),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FilledButton(
                onPressed: picked.isEmpty
                    ? null
                    : () => Navigator.pop(sheet, [
                        for (final c in contacts)
                          if (picked.contains(c.id)) c.asPeer,
                      ]),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
