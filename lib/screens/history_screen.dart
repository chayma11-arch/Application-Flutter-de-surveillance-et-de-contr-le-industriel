import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sensor_history.dart';
import '../services/pdf_export_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final SensorHistoryService _historyService = SensorHistoryService();
  late TabController _tabController;
  String _selectedMetric = 'temperature';
  bool _isLoading = true;
  DateTimeRange? _selectedDateRange;
  String? _username;

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
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _username = user?.displayName ?? user?.email?.split('@').first ?? 'User';
    });
  }

  Future<void> _loadHistory() async {
    await _historyService.loadHistory();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _exportToPDF() async {
    if (_historyService.history.isEmpty) {
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
      final startDate =
          _selectedDateRange?.start ?? _historyService.history.last.timestamp;
      final endDate =
          _selectedDateRange?.end ?? _historyService.history.first.timestamp;

      final file = await PdfExportService.exportSensorHistory(
        history: _historyService.history,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  List<SensorHistoryPoint> _getFilteredHistory() {
    if (_selectedDateRange == null) {
      return _historyService.history;
    }
    return _historyService.history.where((point) {
      return point.timestamp.isAfter(_selectedDateRange!.start) &&
          point.timestamp.isBefore(
            _selectedDateRange!.end.add(const Duration(days: 1)),
          );
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredHistory = _getFilteredHistory();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Data History',
          style: TextStyle(
            color: Color(0xFF1565C0),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Color(0xFF1565C0)),
            onPressed: _showDateRangePicker,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            onPressed: _exportToPDF,
          ),
          if (_selectedDateRange != null)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.grey),
              onPressed: () {
                setState(() {
                  _selectedDateRange = null;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _showClearHistoryDialog(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1565C0),
          labelColor: const Color(0xFF1565C0),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Charts', icon: Icon(Icons.show_chart)),
            Tab(text: 'List', icon: Icon(Icons.list)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChartView(filteredHistory),
                _buildListView(filteredHistory),
              ],
            ),
    );
  }

  Widget _buildChartView(List<SensorHistoryPoint> history) {
    if (history.isEmpty) {
      return Center(
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
      );
    }

    return Column(
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
                      color: isSelected ? Colors.white : metric['color'],
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
            child: LineChart(_buildChartData(history)),
          ),
        ),
      ],
    );
  }

  LineChartData _buildChartData(List<SensorHistoryPoint> history) {
    final metric = _metrics[_selectedMetric]!;

    double getValue(SensorHistoryPoint point) {
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

    final spots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), getValue(history[i])));
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

  Widget _buildListView(List<SensorHistoryPoint> history) {
    if (history.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final point = history[index];
        return Card(
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
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${point.timestamp.month}/${point.timestamp.day}/${point.timestamp.year} ${point.timestamp.hour}:${point.timestamp.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildHistoryChip(
                      Icons.thermostat,
                      '${point.temperature.toStringAsFixed(1)}°C',
                      Colors.red,
                    ),
                    _buildHistoryChip(
                      Icons.water_drop,
                      '${point.humidity.toStringAsFixed(1)}%',
                      Colors.blue,
                    ),
                    _buildHistoryChip(
                      Icons.wb_sunny,
                      '${point.luminosity.toStringAsFixed(0)} lux',
                      Colors.orange,
                    ),
                    _buildHistoryChip(
                      Icons.speed,
                      '${point.pressure.toStringAsFixed(1)} hPa',
                      Colors.purple,
                    ),
                    _buildHistoryChip(
                      Icons.battery_full,
                      '${point.batteryPercent}%',
                      Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history'),
        content: const Text('Do you really want to clear all data history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _historyService.clearHistory();
              if (!mounted) return;
              await _loadHistory();
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('History cleared')));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
