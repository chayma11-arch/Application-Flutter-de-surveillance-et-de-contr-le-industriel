import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlertHistoryItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final String sensorName;
  final double value;
  final double threshold;
  final String unit;

  AlertHistoryItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.sensorName,
    required this.value,
    required this.threshold,
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'sensorName': sensorName,
    'value': value,
    'threshold': threshold,
    'unit': unit,
  };

  factory AlertHistoryItem.fromJson(Map<String, dynamic> json) {
    return AlertHistoryItem(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sensorName: json['sensorName'] as String,
      value: (json['value'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      unit: json['unit'] as String,
    );
  }
}

class AlertHistoryItemAdapter extends TypeAdapter<AlertHistoryItem> {
  @override
  final int typeId = 1;

  @override
  AlertHistoryItem read(BinaryReader reader) {
    return AlertHistoryItem(
      id: reader.readString(),
      title: reader.readString(),
      message: reader.readString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      sensorName: reader.readString(),
      value: reader.readDouble(),
      threshold: reader.readDouble(),
      unit: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, AlertHistoryItem obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.message);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeString(obj.sensorName);
    writer.writeDouble(obj.value);
    writer.writeDouble(obj.threshold);
    writer.writeString(obj.unit);
  }
}

class AlertHistoryService extends ChangeNotifier {
  static const String _legacyStorageKey = 'alert_history';
  static const String _boxName = 'alert_history_box';
  static const int maxHistorySize = 500;
  static bool _initialized = false;

  final List<AlertHistoryItem> _alerts = [];

  List<AlertHistoryItem> get alerts => List.unmodifiable(_alerts);

  Future<void> init() async {
    if (_initialized && Hive.isBoxOpen(_boxName)) return;

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AlertHistoryItemAdapter());
    }
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<AlertHistoryItem>(_boxName);
    }

    _initialized = true;
  }

  Box<AlertHistoryItem> get _box => Hive.box<AlertHistoryItem>(_boxName);

  Future<void> loadHistory() async {
    try {
      await init();
      await _migrateSharedPreferencesHistoryIfNeeded();
      _syncCacheFromBox();
      debugPrint('Alert history loaded from Hive: ${_alerts.length} alerts');
    } catch (e) {
      debugPrint('Error loading alert history: $e');
    }
  }

  void _syncCacheFromBox() {
    _alerts
      ..clear()
      ..addAll(_box.values.toList());
    _alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> _trimHistory() async {
    final sortedEntries = _box.toMap().entries.toList()
      ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));

    if (sortedEntries.length <= maxHistorySize) return;

    final keysToDelete = sortedEntries
        .skip(maxHistorySize)
        .map((entry) => entry.key)
        .toList();
    await _box.deleteAll(keysToDelete);
  }

  Future<void> _migrateSharedPreferencesHistoryIfNeeded() async {
    if (_box.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_legacyStorageKey);
    if (jsonString == null || jsonString.isEmpty) return;

    final List<dynamic> data = json.decode(jsonString);
    final alerts = data
        .map((e) => AlertHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    for (final alert in alerts.take(maxHistorySize)) {
      await _box.put(alert.id, alert);
    }

    await prefs.remove(_legacyStorageKey);
    debugPrint(
      'Migrated ${alerts.length} alerts from SharedPreferences to Hive',
    );
  }

  Future<void> addAlert(AlertHistoryItem alert) async {
    try {
      await init();
      await _box.put(alert.id, alert);
      await _trimHistory();
      _syncCacheFromBox();
      notifyListeners();
      debugPrint('Alert added to history: ${alert.title}');
    } catch (e) {
      debugPrint('Error adding alert: $e');
    }
  }

  Future<void> removeAlert(String id) async {
    try {
      await init();
      await _box.delete(id);
      _syncCacheFromBox();
      notifyListeners();
      debugPrint('Alert $id removed from history');
    } catch (e) {
      debugPrint('Error deleting alert: $e');
    }
  }

  Future<void> clearAllAlerts() async {
    try {
      await init();
      await _box.clear();
      _alerts.clear();
      notifyListeners();
      debugPrint('All alert history cleared');
    } catch (e) {
      debugPrint('Error clearing alert history: $e');
    }
  }

  Future<void> removeAlertsOlderThan(DateTime date) async {
    try {
      await init();
      final keysToDelete = _box.toMap().entries
          .where((entry) => entry.value.timestamp.isBefore(date))
          .map((entry) => entry.key)
          .toList();
      await _box.deleteAll(keysToDelete);
      _syncCacheFromBox();
      notifyListeners();
      debugPrint('Alerts older than $date removed');
    } catch (e) {
      debugPrint('Error deleting old alerts: $e');
    }
  }

  List<AlertHistoryItem> getAlertsBySensorName(String sensorName) {
    return _alerts.where((alert) => alert.sensorName == sensorName).toList();
  }

  List<AlertHistoryItem> getTodayAlerts() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return _alerts
        .where(
          (alert) =>
              alert.timestamp.isAfter(today) &&
              alert.timestamp.isBefore(tomorrow),
        )
        .toList();
  }

  List<AlertHistoryItem> getThisWeekAlerts() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    return _alerts.where((alert) => alert.timestamp.isAfter(weekAgo)).toList();
  }

  bool hasUnreadAlerts() {
    return _alerts.isNotEmpty;
  }

  Map<String, dynamic> getAlertStatistics() {
    final Map<String, int> alertsBySensor = {};
    int totalAlerts = _alerts.length;

    for (var alert in _alerts) {
      alertsBySensor[alert.sensorName] =
          (alertsBySensor[alert.sensorName] ?? 0) + 1;
    }

    return {
      'total': totalAlerts,
      'bySensor': alertsBySensor,
      'mostFrequent': alertsBySensor.entries.isEmpty
          ? null
          : alertsBySensor.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key,
    };
  }
}
