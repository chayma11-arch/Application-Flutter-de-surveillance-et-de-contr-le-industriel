import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  // Singleton
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;

  // Configuration - IDENTIQUE à votre ESP32
  static const String deviceId = 'MSI2026';
  final String broker = 'broker.emqx.io';
  final int port = 1883;
  final String clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';

  // Topics (identiques à l'ESP32 Central)
  final String topicNode1Sensors = 'esp32/$deviceId/node1/sensors';
  final String topicNode1LEDs = 'esp32/$deviceId/node1/leds';
  final String topicNode2MPU = 'esp32/$deviceId/node2/mpu';
  final String topicNode2Servo = 'esp32/$deviceId/node2/servo';
  final String topicStatus = 'esp32/$deviceId/status';

  // Callbacks pour les données
  Function(Map<String, dynamic>)? onNode1Data;
  Function(Map<String, dynamic>)? onNode2Data;
  Function(Map<String, dynamic>)? onCentralStatus;
  Function(bool)? onConnectionChanged;

  bool isConnected = false;

  Future<bool> connect() async {
    try {
      final mqttClient = MqttServerClient(broker, clientId);
      client = mqttClient;
      mqttClient.port = port;
      mqttClient.keepAlivePeriod = 60;
      mqttClient.onDisconnected = _onDisconnected;
      mqttClient.onConnected = _onConnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean();

      mqttClient.connectionMessage = connMessage;

      await mqttClient.connect();

      if (mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
        isConnected = true;
        onConnectionChanged?.call(true);
        _subscribeToTopics();
        mqttClient.updates?.listen(_onMessage);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ MQTT Connection Error: $e');
      isConnected = false;
      onConnectionChanged?.call(false);
      return false;
    }
  }

  void _subscribeToTopics() {
    final mqttClient = client;
    if (mqttClient == null) return;

    mqttClient.subscribe(topicNode1Sensors, MqttQos.atLeastOnce);
    mqttClient.subscribe(topicNode2MPU, MqttQos.atLeastOnce);
    mqttClient.subscribe(topicStatus, MqttQos.atLeastOnce);
    debugPrint('✅ Subscribed to all topics');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var msg in messages) {
      final MqttPublishMessage message = msg.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        message.payload.message,
      );
      final topic = msg.topic;

      try {
        final Map<String, dynamic> data = json.decode(payload);

        if (topic == topicNode1Sensors) {
          onNode1Data?.call(data);
        } else if (topic == topicNode2MPU) {
          onNode2Data?.call(data);
        } else if (topic == topicStatus) {
          onCentralStatus?.call(data);
        }
      } catch (e) {
        debugPrint('JSON Parse Error: $e');
      }
    }
  }

  // Envoyer commande LEDs
  void controlLED({bool? red, bool? yellow, bool? blue}) {
    if (!isConnected) return;

    final data = <String, dynamic>{};
    if (red != null) data['ledRed'] = red;
    if (yellow != null) data['ledYellow'] = yellow;
    if (blue != null) data['ledBlue'] = blue;

    _publish(topicNode1LEDs, json.encode(data));
  }

  // Envoyer commande Servo
  void controlServo({bool? active, int? angle}) {
    if (!isConnected) return;

    final data = <String, dynamic>{};
    if (active != null) data['servoActive'] = active;
    if (angle != null) data['angle'] = angle;

    _publish(topicNode2Servo, json.encode(data));
  }

  void _publish(String topic, String message) {
    final mqttClient = client;
    if (mqttClient == null) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    mqttClient.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('📤 Published to $topic: $message');
  }

  void _onConnected() {
    debugPrint('✅ MQTT Connected to $broker');
    isConnected = true;
    onConnectionChanged?.call(true);
  }

  void _onDisconnected() {
    debugPrint('❌ MQTT Disconnected');
    isConnected = false;
    onConnectionChanged?.call(false);
  }

  void disconnect() {
    client?.disconnect();
    isConnected = false;
  }
}
