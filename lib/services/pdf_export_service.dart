import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../models/sensor_history.dart';
import '../services/alert_history_service.dart';

class PdfExportService {
  // Export sensor history
  static Future<File?> exportSensorHistory({
    required List<SensorHistoryPoint> history,
    required String username,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      // Create the PDF document
      final pdf = pw.Document();

      // Add the main page
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) => [
            _buildHeader(username, startDate, endDate),
            pw.SizedBox(height: 20),
            _buildSummary(history),
            pw.SizedBox(height: 20),
            _buildStatistics(history),
            pw.SizedBox(height: 20),
            _buildHistoryTable(history),
            pw.SizedBox(height: 20),
            _buildFooter(),
          ],
        ),
      );

      // Save the PDF
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'sensor_history_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      debugPrint('✅ PDF exported successfully: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('❌ Error exporting PDF: $e');
      return null;
    }
  }

  // Export alert history
  static Future<File?> exportAlertHistory({
    required List<AlertHistoryItem> alerts,
    required String username,
  }) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) => [
            _buildAlertHeader(username),
            pw.SizedBox(height: 20),
            _buildAlertSummary(alerts),
            pw.SizedBox(height: 20),
            _buildAlertStatistics(alerts),
            pw.SizedBox(height: 20),
            _buildAlertTable(alerts),
            pw.SizedBox(height: 20),
            _buildFooter(),
          ],
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'alert_history_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      debugPrint('✅ Alert PDF exported successfully: ${file.path}');
      return file;
    } catch (e) {
      debugPrint('❌ Error exporting alert PDF: $e');
      return null;
    }
  }

  // Open PDF
  static Future<void> openPDF(File file) async {
    try {
      await OpenFile.open(file.path);
    } catch (e) {
      debugPrint('❌ Error opening PDF: $e');
    }
  }

  // Share PDF
  static Future<void> sharePDF(File file) async {
    try {
      await Printing.sharePdf(
        bytes: await file.readAsBytes(),
        filename: file.path.split('/').last,
      );
    } catch (e) {
      debugPrint('❌ Error sharing PDF: $e');
    }
  }

  // Open and share PDF (compatibility method)
  static Future<void> openAndShare(File file) async {
    await openPDF(file);
  }

  static Future<void> printPDF(File file) async {
    await sharePDF(file);
  }

  // ==================== PDF SECTIONS ====================

  static pw.Widget _buildHeader(
    String username,
    DateTime startDate,
    DateTime endDate,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Container(
            padding: pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              'IoT Sensor Network',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Sensor History Report',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('User: $username'),
        pw.Text('Period: ${_formatDate(startDate)} - ${_formatDate(endDate)}'),
        pw.Text('Export Date: ${_formatDateTime(DateTime.now())}'),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildAlertHeader(String username) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(
          child: pw.Container(
            padding: pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              'IoT Sensor Network - Alerts',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Alert History',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Text('User: $username'),
        pw.Text('Export Date: ${_formatDateTime(DateTime.now())}'),
        pw.Divider(),
      ],
    );
  }

  static pw.Widget _buildSummary(List<SensorHistoryPoint> history) {
    if (history.isEmpty) {
      return pw.Container(
        padding: pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Center(child: pw.Text('No data available')),
      );
    }

    final latest = history.first;

    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Data Summary',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryCard(
                'Latest Measurement',
                _formatDateTime(latest.timestamp),
              ),
              _buildSummaryCard('Data Points', '${history.length}'),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryCard(
                'Temperature',
                '${latest.temperature.toStringAsFixed(1)}°C',
              ),
              _buildSummaryCard(
                'Humidity',
                '${latest.humidity.toStringAsFixed(1)}%',
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryCard(
                'Luminosity',
                '${latest.luminosity.toStringAsFixed(0)} lux',
              ),
              _buildSummaryCard(
                'Pressure',
                '${latest.pressure.toStringAsFixed(1)} hPa',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAlertSummary(List<AlertHistoryItem> alerts) {
    if (alerts.isEmpty) {
      return pw.Container(
        padding: pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Center(child: pw.Text('No recorded alerts')),
      );
    }

    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.red50,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Alert Summary',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryCard('Total alerts', '${alerts.length}'),
              _buildSummaryCard(
                'Last alert',
                _formatRelativeDate(alerts.first.timestamp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatistics(List<SensorHistoryPoint> history) {
    if (history.isEmpty) {
      return pw.Container();
    }

    final avgTemp =
        history.map((e) => e.temperature).reduce((a, b) => a + b) /
        history.length;
    final avgHum =
        history.map((e) => e.humidity).reduce((a, b) => a + b) / history.length;
    final avgLum =
        history.map((e) => e.luminosity).reduce((a, b) => a + b) /
        history.length;
    final maxTemp = history
        .map((e) => e.temperature)
        .reduce((a, b) => a > b ? a : b);
    final minTemp = history
        .map((e) => e.temperature)
        .reduce((a, b) => a < b ? a : b);
    final maxHum = history
        .map((e) => e.humidity)
        .reduce((a, b) => a > b ? a : b);
    final minHum = history
        .map((e) => e.humidity)
        .reduce((a, b) => a < b ? a : b);

    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue200),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Detailed statistics',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 10),
          _buildStatRow(
            'Temperature',
            '${avgTemp.toStringAsFixed(1)}°C',
            '${minTemp.toStringAsFixed(1)}°C',
            '${maxTemp.toStringAsFixed(1)}°C',
          ),
          pw.SizedBox(height: 8),
          _buildStatRow(
            'Humidity',
            '${avgHum.toStringAsFixed(1)}%',
            '${minHum.toStringAsFixed(1)}%',
            '${maxHum.toStringAsFixed(1)}%',
          ),
          pw.SizedBox(height: 8),
          _buildStatRow(
            'Luminosity',
            '${avgLum.toStringAsFixed(0)} lux',
            '-',
            '-',
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAlertStatistics(List<AlertHistoryItem> alerts) {
    if (alerts.isEmpty) {
      return pw.Container();
    }

    // Count alerts by type
    final Map<String, int> alertsByType = {};
    for (var alert in alerts) {
      alertsByType[alert.sensorName] =
          (alertsByType[alert.sensorName] ?? 0) + 1;
    }

    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.orange200),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Alerts by sensor',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.orange800,
            ),
          ),
          pw.SizedBox(height: 10),
          ...alertsByType.entries.map(
            (entry) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(entry.key),
                pw.Container(
                  padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange100,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text('${entry.value} alerts'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildHistoryTable(List<SensorHistoryPoint> history) {
    if (history.isEmpty) {
      return pw.Container();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Measurement Details',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: [
            'Date/Time',
            'Temperature',
            'Humidity',
            'Luminosity',
            'Pressure',
            'Battery',
          ],
          data: history
              .take(20)
              .map(
                (point) => [
                  _formatDateTimeShort(point.timestamp),
                  '${point.temperature.toStringAsFixed(1)}°C',
                  '${point.humidity.toStringAsFixed(1)}%',
                  '${point.luminosity.toStringAsFixed(0)} lux',
                  '${point.pressure.toStringAsFixed(1)} hPa',
                  '${point.batteryPercent}%',
                ],
              )
              .toList(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
          ),
          cellStyle: pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.center,
          headerDecoration: pw.BoxDecoration(color: PdfColors.blue100),
        ),
        if (history.length > 20)
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Note: Only the latest 20 measurements are shown',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ),
      ],
    );
  }

  static pw.Widget _buildAlertTable(List<AlertHistoryItem> alerts) {
    if (alerts.isEmpty) {
      return pw.Container();
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Alert List',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Date/Time', 'Sensor', 'Value', 'Threshold', 'Message'],
          data: alerts
              .map(
                (alert) => [
                  _formatDateTimeShort(alert.timestamp),
                  alert.sensorName,
                  '${alert.value.toStringAsFixed(1)} ${alert.unit}',
                  '${alert.threshold.toStringAsFixed(1)} ${alert.unit}',
                  alert.message.length > 30
                      ? '${alert.message.substring(0, 30)}...'
                      : alert.message,
                ],
              )
              .toList(),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
          ),
          cellStyle: pw.TextStyle(fontSize: 10),
          cellAlignment: pw.Alignment.center,
          headerDecoration: pw.BoxDecoration(color: PdfColors.red100),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Text(
            'Document generated automatically by IoT Sensor Network',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            '© ${DateTime.now().year} - All rights reserved',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
      ],
    );
  }

  // ==================== COMPOSANTS UTILITAIRES ====================

  static pw.Widget _buildSummaryCard(String label, String value) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildStatRow(
    String label,
    String avg,
    String min,
    String max,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Expanded(
          child: pw.Text('Avg: $avg', textAlign: pw.TextAlign.center),
        ),
        pw.Expanded(
          child: pw.Text('Min: $min', textAlign: pw.TextAlign.center),
        ),
        pw.Expanded(
          child: pw.Text('Max: $max', textAlign: pw.TextAlign.center),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _formatDateTime(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateTimeShort(DateTime date) {
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  static String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';

    return _formatDate(date);
  }
}
