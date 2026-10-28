import 'package:av_chat/domain/entities/group.dart';

abstract interface class GroupRepository {
  Future<List<Group>> load();
  Future<void> saveAll(List<Group> groups);
}
