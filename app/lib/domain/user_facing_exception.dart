/// Something the user did that we refuse, with a message to show them.
final class UserFacingException implements Exception {
  const UserFacingException(this.message);
  final String message;

  @override
  String toString() => message;
}
