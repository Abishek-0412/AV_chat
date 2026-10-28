/// What the phone shows outside the app. Never includes message text
/// or names, only that something happened.
abstract interface class SystemAlerts {
  Future<void> init();

  /// Keeps the connection alive while the app is open but not on screen.
  Future<void> startKeepAlive();
  Future<void> stopKeepAlive();

  /// Allows the microphone to keep working in the background during a call.
  Future<void> setInCall({required bool inCall});

  Future<void> newMessage();
  Future<void> incomingCall();
  Future<void> clear();
}

final class NoSystemAlerts implements SystemAlerts {
  const NoSystemAlerts();
  @override
  Future<void> init() async {}
  @override
  Future<void> startKeepAlive() async {}
  @override
  Future<void> stopKeepAlive() async {}
  @override
  Future<void> setInCall({required bool inCall}) async {}
  @override
  Future<void> newMessage() async {}
  @override
  Future<void> incomingCall() async {}
  @override
  Future<void> clear() async {}
}
