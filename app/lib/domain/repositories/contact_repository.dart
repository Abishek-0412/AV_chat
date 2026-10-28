import 'package:av_chat/domain/entities/contact.dart';

abstract interface class ContactRepository {
  Future<List<Contact>> load();
  Future<void> saveAll(List<Contact> contacts);
}
