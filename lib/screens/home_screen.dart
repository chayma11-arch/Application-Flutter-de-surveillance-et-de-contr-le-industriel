import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/mqtt_service.dart';
import '../services/alert_service.dart';
import '../models/sensor_history.dart';
import '../services/pdf_export_service.dart';
import '../services/alert_history_service.dart';
import 'dart:io';

// ==================== MODÈLES DE DONNÉES ====================

class Node1Data {
  double luminosity;
  double humidity;
  double temperature;
  double pressure;
  bool ledRed;
  bool ledYellow;
  bool ledBlue;

  Node1Data({
    this.luminosity = 500.0,
    this.humidity = 55.0,
    this.temperature = 25.5,
    this.pressure = 1013.25,
    this.ledRed = false,
    this.ledYellow = false,
    this.ledBlue = false,
  });

  factory Node1Data.fromJson(Map<String, dynamic> json) {
    return Node1Data(
      temperature: (json['temperature'] ?? 25.0).toDouble(),
      humidity: (json['humidity'] ?? 50.0).toDouble(),
      pressure: (json['pressure'] ?? 1013.0).toDouble(),
      luminosity: (json['luminosity'] ?? 500.0).toDouble(),
      ledRed: json['ledRed'] ?? false,
      ledYellow: json['ledYellow'] ?? false,
      ledBlue: json['ledBlue'] ?? false,
    );
  }
}

class Node2Data {
  double servoAngle;
  bool servoActive;

  Node2Data({this.servoAngle = 0.0, this.servoActive = false});

  factory Node2Data.fromJson(Map<String, dynamic> json) {
    return Node2Data(
      servoAngle: (json['angle'] ?? 0.0).toDouble(),
      servoActive: json['servoActive'] ?? false,
    );
  }
}

class CentralStatus {
  int batteryPercent;
  double batteryVoltage;
  bool bleNode1;
  bool bleNode2;
  int wifiRSSI;
  bool autoMode;

  CentralStatus({
    this.batteryPercent = 0,
    this.batteryVoltage = 0.0,
    this.bleNode1 = false,
    this.bleNode2 = false,
    this.wifiRSSI = 0,
    this.autoMode = true,
  });

  factory CentralStatus.fromJson(Map<String, dynamic> json) {
    return CentralStatus(
      batteryPercent: json['batteryPercent'] ?? 0,
      batteryVoltage: (json['batteryVoltage'] ?? 0.0).toDouble(),
      bleNode1: json['bleNode1'] ?? false,
      bleNode2: json['bleNode2'] ?? false,
      wifiRSSI: json['wifiRSSI'] ?? 0,
      autoMode: json['autoMode'] ?? true,
    );
  }
}

// ==================== HOME SCREEN WITH TABS ====================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Tab selection
  int _selectedTabIndex = 0;
  late TabController _tabController;

  // Node selection
  String _selectedNode = 'Node 1';
  final List<String> _nodes = ['Node 1', 'Node 2'];

  // Data from MQTT
  Node1Data node1Data = Node1Data();
  Node2Data node2Data = Node2Data();
  CentralStatus centralStatus = CentralStatus();

  // Historiques pour graphiques
  final List<double> _tempHistory = List.generate(10, (_) => 25.0);
  final List<double> _humHistory = List.generate(10, (_) => 50.0);
  final List<double> _lumHistory = List.generate(10, (_) => 500.0);
  final List<double> _angleHistory = List.generate(10, (_) => 0.0);

  // Animation Controllers
  late AnimationController _mainAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Services
  final MqttService _mqttService = MqttService();
  final AlertService _alertService = AlertService();
  final SensorHistoryService _sensorHistoryService = SensorHistoryService();
  Timer? _periodicSaveTimer;

  late Future<List<AlertHistoryItem>> _alertsFuture;

  bool _mqttConnected = false;
  String? _username;

  // Alert thresholds (corrigé: camelCase)
  static const double tempMax = 25.0;
  static const double humMax = 35.0;
  static const double humMin = 20.0;
  static const double lumMin = 10.0;
  static const double angleMax = 25.0;

  // Avoid duplicate notifications
  bool _tempAlertSent = false;
  bool _humHighSent = false;
  bool _humLowSent = false;
  bool _lumLowSent = false;
  bool _angleSent = false;

  // History filters
  DateTimeRange? _selectedDateRange;
  String _selectedMetric = 'temperature';

  final Map<String, Map<String, dynamic>> _metrics = {
    'temperature': {
      'icon': Icons.thermostat,
      'color': Colors.red,
      'unit': '°C',
      'label': 'Temperature',
    },
    'humidity': {
      'icon': Icons.water_drop,
      'color': Colors.blue,
      'unit': '%',
      'label': 'Humidity',
    },
    'luminosity': {
      'icon': Icons.wb_sunny,
      'color': Colors.orange,
      'unit': 'lux',
      'label': 'Luminosity',
    },
    'pressure': {
      'icon': Icons.speed,
      'color': Colors.purple,
      'unit': 'hPa',
      'label': 'Pressure',
    },
    'battery': {
      'icon': Icons.battery_full,
      'color': Colors.green,
      'unit': '%',
      'label': 'Battery',
    },
  };

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });

    _mainAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _mainAnimationController,
      curve: Curves.easeInOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _mainAnimationController.forward();

    _connectMQTT();
    _loadSensorHistory();
    _startPeriodicSave();
    _loadUserInfo();
    _alertsFuture = _loadAlerts();
    _alertService.historyService.addListener(_refreshAlerts);
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _username = user?.displayName ?? user?.email?.split('@').first ?? 'User';
    });
  }

  Future<void> _connectMQTT() async {
    _mqttService.onNode1Data = (data) {
      if (mounted) {
        setState(() {
          node1Data = Node1Data.fromJson(data);
          _tempHistory.removeAt(0);
          _tempHistory.add(node1Data.temperature);
          _humHistory.removeAt(0);
          _humHistory.add(node1Data.humidity);
          _lumHistory.removeAt(0);
          _lumHistory.add(node1Data.luminosity);
        });
        _checkThresholds();
      }
    };

    _mqttService.onNode2Data = (data) {
      if (mounted) {
        setState(() {
          node2Data = Node2Data.fromJson(data);
          _angleHistory.removeAt(0);
          _angleHistory.add(node2Data.servoAngle);
        });
        _checkThresholds();
      }
    };

    _mqttService.onCentralStatus = (data) {
      if (mounted) {
        setState(() {
          centralStatus = CentralStatus.fromJson(data);
        });
      }
    };

    _mqttService.onConnectionChanged = (connected) {
      if (mounted) {
        setState(() {
          _mqttConnected = connected;
        });
      }
    };

    await _mqttService.connect();
  }

  // CHECK THRESHOLDS CORRIGÉ
  void _checkThresholds() {
    // Température
    if (node1Data.temperature > tempMax && !_tempAlertSent) {
      _alertService.showThresholdAlert(
        sensorName: 'Temperature',
        value: node1Data.temperature,
        threshold: tempMax,
        unit: '°C',
      );
      _tempAlertSent = true;
    } else if (node1Data.temperature <= tempMax) {
      _tempAlertSent = false;
    }

    // High humidity
    if (node1Data.humidity > humMax && !_humHighSent) {
      _alertService.showThresholdAlert(
        sensorName: 'Humidity',
        value: node1Data.humidity,
        threshold: humMax,
        unit: '%',
      );
      _humHighSent = true;
    } else if (node1Data.humidity <= humMax) {
      _humHighSent = false;
    }

    // Low humidity
    if (node1Data.humidity < humMin && !_humLowSent) {
      _alertService.showThresholdAlert(
        sensorName: 'Humidity',
        value: node1Data.humidity,
        threshold: humMin,
        unit: '%',
      );
      _humLowSent = true;
    } else if (node1Data.humidity >= humMin) {
      _humLowSent = false;
    }

    // Low light
    if (node1Data.luminosity < lumMin && !_lumLowSent) {
      _alertService.showThresholdAlert(
        sensorName: 'Light',
        value: node1Data.luminosity,
        threshold: lumMin,
        unit: 'lux',
      );
      _lumLowSent = true;
    } else if (node1Data.luminosity >= lumMin) {
      _lumLowSent = false;
    }

    // Tilt
    if (node2Data.servoAngle.abs() > angleMax && !_angleSent) {
      _alertService.showThresholdAlert(
        sensorName: 'Tilt',
        value: node2Data.servoAngle.abs(),
        threshold: angleMax,
        unit: '°',
      );
      _angleSent = true;
    } else if (node2Data.servoAngle.abs() <= angleMax) {
      _angleSent = false;
    }
  }

  Future<void> _loadSensorHistory() async {
    await _sensorHistoryService.loadHistory();
  }

  void _startPeriodicSave() {
    _periodicSaveTimer = Timer.periodic(const Duration(minutes: 1), (
      timer,
    ) async {
      if (mounted) {
        await _saveCurrentDataToHistory();
      }
    });
  }

  Future<void> _saveCurrentDataToHistory() async {
    final point = SensorHistoryPoint(
      nodeId: 'Node 1',
      timestamp: DateTime.now(),
      temperature: node1Data.temperature,
      humidity: node1Data.humidity,
      luminosity: node1Data.luminosity,
      pressure: node1Data.pressure,
      batteryPercent: centralStatus.batteryPercent,
    );
    await _sensorHistoryService.addPoint(point);
  }

  @override
  void dispose() {
    _alertService.historyService.removeListener(_refreshAlerts);
    _tabController.dispose();
    _mainAnimationController.dispose();
    _pulseController.dispose();
    _periodicSaveTimer?.cancel();
    _mqttService.disconnect();
    super.dispose();
  }

  void _refreshAlerts() {
    if (!mounted) return;
    setState(() {
      _alertsFuture = _loadAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildDashboard(),
          _buildHistoryTab(),
          _buildAlertsTab(),
          _buildAccountTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ==================== APP BAR ====================
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.sensors, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IoT Sensor Network',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'MQTT Live Data',
                style: TextStyle(
                  color: Color(0xFF64B5F6),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _mqttConnected ? Icons.cloud_done : Icons.cloud_off,
            color: _mqttConnected ? Colors.green : Colors.red,
          ),
          onPressed: () {
            if (!_mqttConnected) _connectMQTT();
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ==================== BOTTOM NAVIGATION BAR ====================
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) {
          setState(() {
            _selectedTabIndex = index;
            _tabController.animateTo(index);
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1E88E5),
        unselectedItemColor: Colors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            activeIcon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_active),
            activeIcon: Icon(Icons.notifications_active),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            activeIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  // ==================== DASHBOARD TAB ====================
  Widget _buildDashboard() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(scale: _scaleAnimation.value, child: child),
        );
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCentralStatusBanner(),
            const SizedBox(height: 16),
            _buildNodeSelector(),
            const SizedBox(height: 20),
            if (_selectedNode == 'Node 1') _buildNode1Dashboard(),
            if (_selectedNode == 'Node 2') _buildNode2Dashboard(),
          ],
        ),
      ),
    );
  }

  // ==================== CENTRAL STATUS BANNER ====================
  Widget _buildCentralStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _mqttConnected
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.red.shade400, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_mqttConnected ? Colors.green : Colors.red).withOpacity(
              0.3,
            ),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _mqttConnected ? Icons.cloud_done : Icons.cloud_off,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _mqttConnected ? 'MQTT Connected' : 'MQTT Disconnected',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.battery_charging_full,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            '${centralStatus.batteryPercent}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: centralStatus.autoMode
                  ? Colors.white.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              centralStatus.autoMode ? 'AUTO' : 'MANUAL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildMiniDot(centralStatus.bleNode1, 'N1'),
          const SizedBox(width: 8),
          _buildMiniDot(centralStatus.bleNode2, 'N2'),
        ],
      ),
    );
  }

  Widget _buildMiniDot(bool isConnected, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? Colors.greenAccent : Colors.redAccent,
            boxShadow: [
              BoxShadow(
                color: (isConnected ? Colors.greenAccent : Colors.redAccent)
                    .withOpacity(0.6),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  // ==================== NODE SELECTOR ====================
  Widget _buildNodeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: _nodes.map((node) {
          final isSelected = _selectedNode == node;
          final nodeNumber = node.split(' ').last;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedNode = node;
                  _mainAnimationController.reset();
                  _mainAnimationController.forward();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1565C0).withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSelected ? Icons.router : Icons.router_outlined,
                      color: isSelected ? Colors.white : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Text(
                          'Node $nodeNumber',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          node == 'Node 1'
                              ? 'BME280 + BH1750'
                              : 'MPU6050 + Servo',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white70
                                : Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ==================== NODE 1 DASHBOARD ====================
  Widget _buildNode1Dashboard() {
    return Column(
      children: [
        _buildNodeInfoCard(
          'Node 1 - Environmental Sensors',
          'BH1750 Light Sensor + BME280 Temp/Hum/Pressure',
          Icons.thermostat,
          const Color(0xFF1565C0),
        ),
        const SizedBox(height: 16),
        _buildNode1SensorGrid(),
        const SizedBox(height: 20),
        _buildNode1Charts(),
        const SizedBox(height: 20),
        _buildNode1LEDControl(),
        const SizedBox(height: 20),
        _buildNode1PressureCard(),
      ],
    );
  }

  Widget _buildNodeInfoCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            centralStatus.bleNode1
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildNode1SensorGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                'Temperature',
                '${node1Data.temperature.toStringAsFixed(1)}°C',
                Icons.thermostat,
                const Color(0xFFE53935),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                'Humidity',
                '${node1Data.humidity.toStringAsFixed(1)}%',
                Icons.water_drop,
                const Color(0xFF1E88E5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSensorCard(
                'Luminosity',
                '${node1Data.luminosity.toStringAsFixed(0)} lux',
                Icons.wb_sunny,
                const Color(0xFFF57C00),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSensorCard(
                'Pressure',
                '${node1Data.pressure.toStringAsFixed(1)} hPa',
                Icons.speed,
                const Color(0xFF7B1FA2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNode1Charts() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: Color(0xFF1565C0), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Temperature Trend',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}°',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: _tempHistory.reduce((a, b) => a < b ? a : b) - 1,
                maxY: _tempHistory.reduce((a, b) => a > b ? a : b) + 1,
                lineBarsData: [
                  LineChartBarData(
                    spots: _tempHistory
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    isCurved: true,
                    color: const Color(0xFFE53935),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFE53935).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode1LEDControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, color: Color(0xFF1565C0), size: 20),
              const SizedBox(width: 8),
              const Text(
                'LED Control Panel',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLEDControl('Red LED', node1Data.ledRed, Colors.red, () {
                setState(() => node1Data.ledRed = !node1Data.ledRed);
                _mqttService.controlLED(red: node1Data.ledRed);
              }),
              _buildLEDControl(
                'Yellow LED',
                node1Data.ledYellow,
                Colors.amber,
                () {
                  setState(() => node1Data.ledYellow = !node1Data.ledYellow);
                  _mqttService.controlLED(yellow: node1Data.ledYellow);
                },
              ),
              _buildLEDControl('Blue LED', node1Data.ledBlue, Colors.blue, () {
                setState(() => node1Data.ledBlue = !node1Data.ledBlue);
                _mqttService.controlLED(blue: node1Data.ledBlue);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLEDControl(
    String label,
    bool isActive,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseOpacity = isActive
              ? 0.7 + (_pulseController.value * 0.3)
              : 0.3;
          return Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? color.withOpacity(pulseOpacity)
                      : Colors.grey.shade200,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withOpacity(
                              0.4 * _pulseController.value,
                            ),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? color : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withOpacity(0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: isActive ? color : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNode1PressureCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1565C0).withOpacity(0.1),
            const Color(0xFF42A5F5).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1565C0).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, color: Color(0xFF1565C0), size: 24),
              const SizedBox(width: 12),
              const Text(
                'Atmospheric Pressure',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                node1Data.pressure.toStringAsFixed(1),
                style: const TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'hPa',
                  style: TextStyle(color: Color(0xFF64B5F6), fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ((node1Data.pressure - 950) / 100)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              backgroundColor: const Color(0xFF1565C0).withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF1565C0),
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== NODE 2 DASHBOARD ====================
  Widget _buildNode2Dashboard() {
    return Column(
      children: [
        _buildNodeInfoCard(
          'Node 2 - Motion Control',
          'MPU6050 Gyroscope + Servo Motor',
          Icons.precision_manufacturing,
          const Color(0xFF00897B),
        ),
        const SizedBox(height: 16),
        _buildNode2AngleCard(),
        const SizedBox(height: 20),
        _buildNode2AngleChart(),
        const SizedBox(height: 20),
        _buildNode2ServoControl(),
      ],
    );
  }

  Widget _buildNode2AngleCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.teal.withOpacity(0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors, color: Color(0xFF00897B), size: 20),
              const SizedBox(width: 8),
              const Text(
                'MPU6050 - Current Angle',
                style: TextStyle(
                  color: Color(0xFF00897B),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Servo: ${node2Data.servoActive ? "ON" : "OFF"}',
                style: TextStyle(
                  color: node2Data.servoActive ? Colors.green : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Transform.rotate(
              angle: node2Data.servoAngle * (3.14159 / 180),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00897B).withOpacity(0.3),
                      const Color(0xFF4DB6AC).withOpacity(0.1),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFF00897B).withOpacity(0.5),
                    width: 3,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.navigation,
                    color: Color(0xFF00897B),
                    size: 60,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${node2Data.servoAngle.toStringAsFixed(1)}°',
              style: const TextStyle(
                color: Color(0xFF00897B),
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode2AngleChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.teal.withOpacity(0.05), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Angle History',
            style: TextStyle(
              color: Color(0xFF00897B),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}°',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: -90,
                maxY: 90,
                lineBarsData: [
                  LineChartBarData(
                    spots: _angleHistory
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    isCurved: true,
                    color: const Color(0xFF00897B),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF00897B).withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode2ServoControl() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF00897B).withOpacity(0.1),
            const Color(0xFF4DB6AC).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00897B).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.settings, color: Color(0xFF00897B), size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Servo Motor Control',
                  style: TextStyle(
                    color: Color(0xFF00897B),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Switch(
                value: node2Data.servoActive,
                onChanged: (v) {
                  setState(() => node2Data.servoActive = v);
                  _mqttService.controlServo(active: v);
                },
                activeThumbColor: const Color(0xFF00897B),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            node2Data.servoActive ? 'Motor Active' : 'Motor Stopped',
            style: TextStyle(
              color: node2Data.servoActive
                  ? const Color(0xFF00897B)
                  : Colors.grey,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    final filteredHistory = _getFilteredHistory();

    return Column(
      children: [
        // Filters
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showDateRangePicker,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _selectedDateRange == null
                        ? 'All dates'
                        : '${_formatDateShort(_selectedDateRange!.start)} - ${_formatDateShort(_selectedDateRange!.end)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1565C0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                onPressed: _exportHistoryToPDF,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              if (_selectedDateRange != null)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _selectedDateRange = null;
                    });
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Graphique et liste
        Expanded(
          child: filteredHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.history, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No data in this period',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedDateRange != null)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedDateRange = null;
                            });
                          },
                          child: const Text('Show all data'),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Sélecteur de métrique
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Wrap(
                        spacing: 8,
                        children: _metrics.keys.map((key) {
                          final metric = _metrics[key]!;
                          final isSelected = _selectedMetric == key;
                          return FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  metric['icon'],
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : metric['color'],
                                ),
                                const SizedBox(width: 4),
                                Text(metric['label']),
                              ],
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedMetric = key;
                              });
                            },
                            backgroundColor: Colors.grey.shade100,
                            selectedColor: metric['color'],
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    // Graphique
                    Expanded(
                      flex: 2,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: LineChart(_buildChartData(filteredHistory)),
                      ),
                    ),
                    // Liste des valeurs
                    Expanded(
                      flex: 1,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredHistory.length > 10
                            ? 10
                            : filteredHistory.length,
                        itemBuilder: (context, index) {
                          final point = filteredHistory[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: Icon(
                                _metrics[_selectedMetric]!['icon'],
                                color: _metrics[_selectedMetric]!['color'],
                              ),
                              title: Text(
                                _getMetricValue(point).toStringAsFixed(1) +
                                    _metrics[_selectedMetric]!['unit'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              trailing: Text(
                                '${point.timestamp.hour}:${point.timestamp.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  List<SensorHistoryPoint> _getFilteredHistory() {
    if (_selectedDateRange == null) {
      return _sensorHistoryService.history;
    }
    return _sensorHistoryService.history.where((point) {
      return point.timestamp.isAfter(_selectedDateRange!.start) &&
          point.timestamp.isBefore(
            _selectedDateRange!.end.add(const Duration(days: 1)),
          );
    }).toList();
  }

  // CORRIGÉ: retourne double
  double _getMetricValue(SensorHistoryPoint point) {
    switch (_selectedMetric) {
      case 'temperature':
        return point.temperature;
      case 'humidity':
        return point.humidity;
      case 'luminosity':
        return point.luminosity;
      case 'pressure':
        return point.pressure;
      case 'battery':
        return point.batteryPercent.toDouble();
      default:
        return 0.0;
    }
  }

  LineChartData _buildChartData(List<SensorHistoryPoint> history) {
    final metric = _metrics[_selectedMetric]!;

    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), _getMetricValue(history[i])));
    }

    if (spots.isEmpty) {
      return LineChartData(
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [],
      );
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 5;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 5;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(
              '${value.toInt()}${metric['unit']}',
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < history.length) {
                return Text(
                  '${history[index].timestamp.hour}:${history[index].timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey, fontSize: 9),
                );
              }
              return const Text('');
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: metric['color'],
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: (metric['color'] as Color).withOpacity(0.1),
          ),
        ),
      ],
    );
  }

  void _showDateRangePicker() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  Future<void> _exportHistoryToPDF() async {
    final history = _getFilteredHistory();
    if (history.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data to export')));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final startDate = _selectedDateRange?.start ?? history.last.timestamp;
      final endDate = _selectedDateRange?.end ?? history.first.timestamp;

      final file = await PdfExportService.exportSensorHistory(
        history: history,
        username: _username ?? 'User',
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (file != null) {
        _showExportOptions(file);
      } else {
        throw Exception('Error generating PDF');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ==================== ALERTS TAB ====================
  Widget _buildAlertsTab() {
    return FutureBuilder<List<AlertHistoryItem>>(
      future: _alertsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final alerts = snapshot.data ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                    onPressed: () => _exportAlertsToPDF(alerts),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep, color: Colors.red),
                    onPressed: alerts.isNotEmpty
                        ? () => _clearAllAlerts()
                        : null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: alerts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No alerts',
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Alerts will appear here',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: alerts.length,
                      itemBuilder: (context, index) {
                        final alert = alerts[index];
                        return Dismissible(
                          key: Key(alert.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => _deleteAlert(alert.id),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _getAlertColor(
                                            alert,
                                          ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          _getAlertIcon(alert),
                                          color: _getAlertColor(alert),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              alert.title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatRelativeDate(
                                                alert.timestamp,
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 20),
                                        onPressed: () => _deleteAlert(alert.id),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(alert.message),
                                  if (alert.sensorName != 'System') ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.sensors,
                                            size: 14,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${alert.sensorName}: ${alert.value.toStringAsFixed(1)} ${alert.unit} (threshold: ${alert.threshold.toStringAsFixed(1)} ${alert.unit})',
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<List<AlertHistoryItem>> _loadAlerts() async {
    await _alertService.historyService.loadHistory();
    return _alertService.historyService.alerts;
  }

  Future<void> _deleteAlert(String id) async {
    await _alertService.historyService.removeAlert(id);
    if (!mounted) return;
    setState(() {
      _alertsFuture = _loadAlerts();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Alert deleted')));
  }

  Future<void> _clearAllAlerts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all alerts'),
        content: const Text('Do you really want to clear all alert history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      await _alertService.clearAlertHistory();
      if (!mounted) return;
      setState(() {
        _alertsFuture = _loadAlerts();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All alerts have been cleared')),
      );
    }
  }

  Future<void> _exportAlertsToPDF(List<AlertHistoryItem> alerts) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final file = await PdfExportService.exportAlertHistory(
        alerts: alerts,
        username: _username ?? 'User',
      );

      if (!mounted) return;
      Navigator.pop(context);

      if (file != null) {
        _showExportOptions(file);
      } else {
        throw Exception('Error generating PDF');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  IconData _getAlertIcon(AlertHistoryItem alert) {
    switch (alert.sensorName) {
      case 'Temperature':
        return Icons.thermostat;
      case 'Humidity':
        return Icons.water_drop;
      case 'Light':
        return Icons.wb_sunny;
      case 'Tilt':
        return Icons.sensors;
      default:
        return Icons.notification_important;
    }
  }

  Color _getAlertColor(AlertHistoryItem alert) {
    switch (alert.sensorName) {
      case 'Temperature':
        return Colors.red;
      case 'Humidity':
        return Colors.blue;
      case 'Light':
        return Colors.orange;
      case 'Tilt':
        return Colors.purple;
      default:
        return Colors.amber;
    }
  }

  // ==================== ACCOUNT TAB ====================
  Widget _buildAccountTab() {
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1565C0).withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.person, size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user?.displayName ?? user?.email?.split('@').first ?? 'User',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? 'Not connected',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Connected',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Information card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const Divider(height: 24),
                _buildInfoRow(Icons.email, 'Email', user?.email ?? 'Not set'),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.verified,
                  'Verified',
                  user?.emailVerified == true ? 'Yes' : 'No',
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.calendar_today,
                  'Member since',
                  _formatDate(user?.metadata.creationTime),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Statistics
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const Divider(height: 24),
                _buildInfoRow(
                  Icons.history,
                  'Sensor history',
                  '${_sensorHistoryService.history.length} points',
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.notifications,
                  'Alerts',
                  '${_alertService.historyService.alerts.length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Sign out button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Do you really want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  void _showExportOptions(File file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PDF exported successfully!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: const Text('Open PDF'),
              onTap: () async {
                Navigator.pop(context);
                await PdfExportService.openAndShare(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(context);
                await PdfExportService.printPDF(file);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateShort(DateTime date) {
    return '${date.day}/${date.month}';
  }

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}
