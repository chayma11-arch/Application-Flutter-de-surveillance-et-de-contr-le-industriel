import 'package:flutter/foundation.dart';
import 'notification_service.dart';
import 'alert_history_service.dart';

class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  NotificationService? _notificationService;
  final AlertHistoryService _historyService = AlertHistoryService();
  bool _isInitialized = false;

  // Default thresholds
  static const Map<String, double> defaultThresholds = {
    'Temperature': 25.0,
    'Humidity': 35.0,
    'Light': 10.0,
    'Tilt': 25.0,
  };

  // Avoid duplicate notifications
  final Map<String, bool> _alertSentStatus = {};
  final Map<String, DateTime> _lastAlertTime = {};

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _notificationService = NotificationService();
      await _notificationService!.initialize();
      await _historyService.loadHistory();
      _isInitialized = true;
      debugPrint('✅ AlertService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing AlertService: $e');
      rethrow;
    }
  }

  AlertHistoryService get historyService => _historyService;

  // Reset alert status
  void resetAlertStatus(String sensorName) {
    _alertSentStatus[sensorName] = false;
  }

  void resetAllAlertStatus() {
    _alertSentStatus.clear();
  }

  Future<void> showThresholdAlert({
    required String sensorName,
    required double value,
    required double threshold,
    required String unit,
    bool isExceeded = true,
  }) async {
    if (!_isInitialized) {
      debugPrint('❌ AlertService not initialized. Call init() first.');
      return;
    }

    if (_notificationService == null) {
      debugPrint('❌ NotificationService not initialized');
      return;
    }

    try {
      final String alertType = isExceeded ? 'exceeded' : 'back to normal';
      final String alertEmoji = isExceeded ? '🚨' : 'ℹ️';

      debugPrint(
        '$alertEmoji Alert $alertType: $sensorName $value $unit (threshold: $threshold $unit)',
      );

      // Debounce: avoid sending multiple notifications too frequently per sensor
      final now = DateTime.now();
      final last = _lastAlertTime[sensorName];
      if (last != null && now.difference(last) < const Duration(seconds: 30)) {
        debugPrint('⏱️ Skipping alert for $sensorName (cooldown)');
        return;
      }

      // Generate a unique ID based on the sensor and timestamp
      final int id = '$sensorName-${DateTime.now().millisecondsSinceEpoch}'
          .hashCode
          .abs();

      final String title = isExceeded
          ? '⚠️ $sensorName alert'
          : '✅ Back to normal - $sensorName';

      final String body = isExceeded
          ? '$sensorName exceeded the threshold: ${value.toStringAsFixed(1)}$unit (threshold: ${threshold.toStringAsFixed(1)}$unit)'
          : '$sensorName returned below the threshold: ${value.toStringAsFixed(1)}$unit (threshold: ${threshold.toStringAsFixed(1)}$unit)';

      // Save to history
      final alertItem = AlertHistoryItem(
        id: id.toString(),
        title: title,
        message: body,
        timestamp: DateTime.now(),
        sensorName: sensorName,
        value: value,
        threshold: threshold,
        unit: unit,
      );
      await _historyService.addAlert(alertItem);

      // Envoyer la notification

      await _notificationService!.showAlertNotification(
        id: id,
        title: title,
        body: body,
        isCritical: isExceeded, // use critical channel when exceeded
      );

      _lastAlertTime[sensorName] = now;

      debugPrint('✅ Notification sent for $sensorName');
    } catch (e) {
      debugPrint('❌ Error sending alert: $e');
    }
  }

  Future<void> showAlert({
    required String title,
    required String message,
    int id = 0,
    String sensorName = 'System',
    double value = 0,
    double threshold = 0,
    String unit = '',
  }) async {
    if (!_isInitialized) {
      debugPrint('❌ AlertService not initialized. Call init() first.');
      return;
    }

    if (_notificationService == null) {
      debugPrint('❌ NotificationService not initialized');
      return;
    }

    try {
      final int uniqueId = id != 0
          ? id
          : '${DateTime.now().millisecondsSinceEpoch}'.hashCode.abs();

      // Save all alerts displayed as notifications.
      final alertItem = AlertHistoryItem(
        id: uniqueId.toString(),
        title: title,
        message: message,
        timestamp: DateTime.now(),
        sensorName: sensorName,
        value: value,
        threshold: threshold,
        unit: unit,
      );
      await _historyService.addAlert(alertItem);

      await _notificationService!.showAlertNotification(
        id: uniqueId,
        title: title,
        body: message,
        isCritical: true,
      );

      debugPrint('✅ Alert notification sent: $title');
    } catch (e) {
      debugPrint('❌ Error sending custom alert: $e');
    }
  }

  // Vérifier les seuils avec gestion des doublons
  Future<void> checkAndAlert({
    required String sensorName,
    required double value,
    required double threshold,
    required String unit,
    bool alertOnExceed = true,
  }) async {
    final bool isExceeded = value > threshold;
    final String key = sensorName;

    // Check if the alert has already been sent
    final bool alreadySent = _alertSentStatus[key] ?? false;

    if (alertOnExceed) {
      // Alert when the value exceeds the threshold
      if (isExceeded && !alreadySent) {
        await showThresholdAlert(
          sensorName: sensorName,
          value: value,
          threshold: threshold,
          unit: unit,
          isExceeded: true,
        );
        _alertSentStatus[key] = true;
      } else if (!isExceeded && alreadySent) {
        // Back-to-normal notification
        await showThresholdAlert(
          sensorName: sensorName,
          value: value,
          threshold: threshold,
          unit: unit,
          isExceeded: false,
        );
        _alertSentStatus[key] = false;
      }
    } else {
      // Alert when the value is below the threshold
      final bool isBelow = value < threshold;
      if (isBelow && !alreadySent) {
        await showThresholdAlert(
          sensorName: sensorName,
          value: value,
          threshold: threshold,
          unit: unit,
          isExceeded: false,
        );
        _alertSentStatus[key] = true;
      } else if (!isBelow && alreadySent) {
        _alertSentStatus[key] = false;
      }
    }
  }

  // Clear all alert history
  Future<void> clearAlertHistory() async {
    await _historyService.clearAllAlerts();
    debugPrint('✅ Alert history cleared');
  }

  // Get the number of alerts
  Future<int> getAlertCount() async {
    return _historyService.alerts.length;
  }

  // Get alerts by sensor
  Future<Map<String, int>> getAlertsBySensor() async {
    final Map<String, int> alertsBySensor = {};
    for (var alert in _historyService.alerts) {
      alertsBySensor[alert.sensorName] =
          (alertsBySensor[alert.sensorName] ?? 0) + 1;
    }
    return alertsBySensor;
  }

  // Get recent alerts (last 24h)
  Future<List<AlertHistoryItem>> getRecentAlerts() async {
    final now = DateTime.now();
    final last24h = now.subtract(const Duration(hours: 24));
    return _historyService.alerts
        .where((alert) => alert.timestamp.isAfter(last24h))
        .toList();
  }

  // Delete a specific alert
  Future<void> deleteAlert(String id) async {
    await _historyService.removeAlert(id);
    debugPrint('✅ Alert $id removed');
  }

  // Dispose the service
  void dispose() {
    _notificationService = null;
    _alertSentStatus.clear();
    _isInitialized = false;
    debugPrint('✅ AlertService disposed');
  }
}
