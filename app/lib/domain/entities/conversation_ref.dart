import 'package:av_protocol/av_protocol.dart';
import 'package:meta/meta.dart';

/// Which chat a message belongs to.
@immutable
sealed class ConversationRef {
  const ConversationRef();

  /// Stable key for maps and routes.
  String get key;

  static ConversationRef parse(String key) => switch (key.split(':')) {
    ['d', final id] => DirectRef(AvId.parse(id)),
    ['g', final id] => GroupRef(id),
    _ => throw FormatException('Bad conversation key: $key'),
  };

  @override
  bool operator ==(Object other) =>
      other is ConversationRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

final class DirectRef extends ConversationRef {
  const DirectRef(this.peer);
  final AvId peer;
  @override
  String get key => 'd:${peer.value}';
}

final class GroupRef extends ConversationRef {
  const GroupRef(this.groupId);
  final String groupId;
  @override
  String get key => 'g:$groupId';
}
