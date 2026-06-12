import 'dart:io';

void main() {
  final file = File('lib/services/pdf_export_service.dart');
  print('EXISTS: ${file.existsSync()}');
  print('PATH: ${file.path}');
  final lines = file.readAsLinesSync();
  print('LINE COUNT: ${lines.length}');
  for (var i = 0; i < 40 && i < lines.length; i++) {
    print('LINE ${i + 1}: ${lines[i]}');
    print(lines[i].codeUnits);
  }
}
