import 'package:av_chat/domain/services/system_alerts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Foreground service + content-free notifications.
final class AndroidSystemAlerts implements SystemAlerts {
  static const _messageId = 1001;
  static const _callId = 1002;
  static const _icon = '@drawable/ic_launcher_monochrome';

  final _notifications = FlutterLocalNotificationsPlugin();
  var _running = false;
  var _inCall = false;

  @override
  Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'keep_alive',
        channelName: 'Connection',
        channelDescription: 'Shown while AV Chat is open in the background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWifiLock: true,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
    );
    await FlutterForegroundTask.requestNotificationPermission();
  }

  @override
  Future<void> startKeepAlive() async {
    if (_running) return;
    _running = true;
    await _start();
  }

  @override
  Future<void> stopKeepAlive() async {
    _running = false;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> setInCall({required bool inCall}) async {
    if (inCall == _inCall || !_running) return;
    _inCall = inCall;
    // Service types are fixed at start, so restart with/without mic.
    await FlutterForegroundTask.stopService();
    await _start();
  }

  Future<void> _start() async {
    final mic = _inCall && await Permission.microphone.isGranted;
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [
        ForegroundServiceTypes.dataSync,
        ForegroundServiceTypes.remoteMessaging,
        if (mic) ForegroundServiceTypes.microphone,
      ],
      notificationTitle: 'AV Chat is open',
      notificationText: _inCall
          ? 'Call in progress'
          : 'Chats disappear when you close the app',
      notificationIcon: const NotificationIcon(
        metaDataName: 'com.avchat.av_chat.notification_icon',
      ),
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[alerts] keep-alive failed: ${result.error}');
    }
  }

  @override
  Future<void> newMessage() => _notifications.show(
    id: _messageId,
    title: 'AV Chat',
    body: 'New message',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'New messages (content is never shown)',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.secret,
        category: AndroidNotificationCategory.message,
        icon: _icon,
      ),
    ),
  );

  @override
  Future<void> incomingCall() => _notifications.show(
    id: _callId,
    title: 'AV Chat',
    body: 'Incoming call',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'calls',
        'Calls',
        channelDescription: 'Incoming voice calls',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.secret,
        timeoutAfter: 45000,
        icon: _icon,
      ),
    ),
  );

  @override
  Future<void> clear() async {
    await _notifications.cancel(id: _messageId);
    await _notifications.cancel(id: _callId);
  }
}
