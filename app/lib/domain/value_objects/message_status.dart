/// Lifecycle of a message. Incoming messages start at [delivered].
enum MessageStatus {
  /// Waiting for the encrypted session or the recipient's confirmation.
  sending,

  /// Recipient's app confirmed it arrived.
  delivered,

  /// Recipient opened the chat.
  read,

  /// Recipient was offline; the message was dropped.
  failed,
}
