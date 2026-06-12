import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SensorHistoryPoint {
  final String nodeId;
  final DateTime timestamp;
  final double temperature;
  final double humidity;
  final double luminosity;
  final double pressure;
  final int batteryPercent;
  final Map<String, double> extraSensors;
  final Map<String, bool> actuatorStates;

  SensorHistoryPoint({
    required this.nodeId,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.luminosity,
    required this.pressure,
    required this.batteryPercent,
    this.extraSensors = const {},
    this.actuatorStates = const {},
  });

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'timestamp': timestamp.toIso8601String(),
    'temperature': temperature,
    'humidity': humidity,
    'luminosity': luminosity,
    'pressure': pressure,
    'batteryPercent': batteryPercent,
    'extraSensors': extraSensors,
    'actuatorStates': actuatorStates,
  };

  factory SensorHistoryPoint.fromJson(Map<String, dynamic> json) {
    return SensorHistoryPoint(
      nodeId: json['nodeId'] as String? ?? 'unknown',
      timestamp: DateTime.parse(json['timestamp'] as String),
      temperature: (json['temperature'] as num).toDouble(),
      humidity: (json['humidity'] as num).toDouble(),
      luminosity: (json['luminosity'] as num).toDouble(),
      pressure: (json['pressure'] as num).toDouble(),
      batteryPercent: (json['batteryPercent'] as num).toInt(),
      extraSensors:
          (json['extraSensors'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          {},
      actuatorStates:
          (json['actuatorStates'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
    );
  }
}

class SensorHistoryPointAdapter extends TypeAdapter<SensorHistoryPoint> {
  @override
  final int typeId = 0;

  @override
  SensorHistoryPoint read(BinaryReader reader) {
    return SensorHistoryPoint(
      nodeId: reader.readString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
      temperature: reader.readDouble(),
      humidity: reader.readDouble(),
      luminosity: reader.readDouble(),
      pressure: reader.readDouble(),
      batteryPercent: reader.readInt(),
      extraSensors: Map<String, double>.from(
        (reader.readMap()).cast<String, dynamic>().map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        ),
      ),
      actuatorStates: Map<String, bool>.from(
        (reader.readMap()).cast<String, dynamic>().map(
          (key, value) => MapEntry(key, value as bool),
        ),
      ),
    );
  }

  @override
  void write(BinaryWriter writer, SensorHistoryPoint obj) {
    writer.writeString(obj.nodeId);
    writer.writeInt(obj.timestamp.millisecondsSinceEpoch);
    writer.writeDouble(obj.temperature);
    writer.writeDouble(obj.humidity);
    writer.writeDouble(obj.luminosity);
    writer.writeDouble(obj.pressure);
    writer.writeInt(obj.batteryPercent);
    writer.writeMap(obj.extraSensors);
    writer.writeMap(obj.actuatorStates);
  }
}

class SensorHistoryService {
  static const String _boxName = 'sensor_history_box';
  static const int maxHistorySize = 500;
  static bool _initialized = false;

  final List<SensorHistoryPoint> _history = [];

  List<SensorHistoryPoint> get history => List.unmodifiable(_history);

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SensorHistoryPointAdapter());
    }
    await Hive.openBox<SensorHistoryPoint>(_boxName);
    _initialized = true;
  }

  Box<SensorHistoryPoint> get _box => Hive.box<SensorHistoryPoint>(_boxName);

  Future<void> loadHistory() async {
    try {
      await init();
      _history
        ..clear()
        ..addAll(_box.values.toList());
      _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      debugPrint('✅ Sensor history loaded: ${_history.length} points');
    } catch (e) {
      debugPrint('❌ Error loading sensor history: $e');
    }
  }

  Future<void> addPoint(SensorHistoryPoint point) async {
    try {
      await init();
      await _box.add(point);
      while (_box.length > maxHistorySize) {
        final oldestKey = _box.keys.cast<int>().first;
        await _box.delete(oldestKey);
      }
      await loadHistory();
      debugPrint(
        '✅ History point added: ${point.timestamp} for ${point.nodeId}',
      );
    } catch (e) {
      debugPrint('❌ Error adding history point: $e');
    }
  }

  Future<void> clearHistory() async {
    try {
      await init();
      await _box.clear();
      _history.clear();
      debugPrint('✅ Sensor history cleared');
    } catch (e) {
      debugPrint('❌ Error clearing sensor history: $e');
    }
  }

  List<SensorHistoryPoint> historyForNode(String nodeId) {
    return _history.where((point) => point.nodeId == nodeId).toList();
  }

  List<String> get availableNodes {
    return _history.map((point) => point.nodeId).toSet().toList();
  }
}
