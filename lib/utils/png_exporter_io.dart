import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> savePng(Uint8List bytes, String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final safeName = fileName.trim().isEmpty ? 'export.png' : fileName.trim();
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
