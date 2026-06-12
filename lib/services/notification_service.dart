import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FlutterLocalNotificationsPlugin? _notifications;
  bool _isInitialized = false;

  static const String _channelId = 'iot_alerts';
  static const String _channelName = 'IoT Alerts';
  static const String _channelDesc = 'Threshold exceedance alerts';
  static const String _criticalChannelId = 'iot_alerts_critical';
  static const String _criticalChannelName = 'IoT Alerts (Critical)';

  Future<void> initialize() async {
    if (_isInitialized) return;

    _notifications = FlutterLocalNotificationsPlugin();

    // Create two channels: normal (no vibration) and critical (vibrate)
    final androidPlugin = _notifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      final normalChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        showBadge: true,
        enableVibration: false,
        vibrationPattern: Int64List.fromList([0]),
        playSound: true,
      );

      final criticalChannel = AndroidNotificationChannel(
        _criticalChannelId,
        _criticalChannelName,
        description: 'Critical threshold alerts (vibrate)',
        importance: Importance.high,
        showBadge: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        playSound: true,
      );

      await androidPlugin.createNotificationChannel(normalChannel);
      await androidPlugin.createNotificationChannel(criticalChannel);
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications!.initialize(settings: settings);
    _isInitialized = true;
  }

  Future<bool> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final androidPlugin = _notifications!
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        final bool granted =
            (await androidPlugin.requestNotificationsPermission()) ?? false;
        return granted;
      }

      // On iOS, permissions are requested during initialization
      return true;
    } catch (e) {
      debugPrint('❌ Error requesting notification permissions: $e');
      return false;
    }
  }

  Future<void> showAlertNotification({
    required int id,
    required String title,
    required String body,
    bool isCritical = false,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_notifications == null) {
      debugPrint('❌ Notifications not initialized');
      return;
    }

    try {
      final channelId = isCritical ? _criticalChannelId : _channelId;
      final channelName = isCritical ? _criticalChannelName : _channelName;
      final channelDesc = isCritical
          ? 'Critical threshold alerts (vibrate)'
          : _channelDesc;

      // If the app is in foreground and the alert is not critical,
      // skip showing a system notification to avoid device vibration while
      // the user is actively in the app.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !isCritical) {
        debugPrint(
          'ℹ️ App in foreground — skipping non-critical system notification',
        );
        return;
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        showWhen: true,
        enableVibration: isCritical,
        vibrationPattern: isCritical
            ? Int64List.fromList([0, 500, 200, 500])
            : Int64List.fromList([0]),
        playSound: true,
        autoCancel: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications!.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('❌ Error showing notification: $e');
    }
  }

  Future<void> cancelAll() async {
    if (_notifications != null && _isInitialized) {
      await _notifications!.cancelAll();
    }
  }

  Future<void> cancel(int id) async {
    if (_notifications != null && _isInitialized) {
      await _notifications!.cancel(id: id);
    }
  }

  Future<void> dispose() async {
    await cancelAll();
    _notifications = null;
    _isInitialized = false;
  }
}
