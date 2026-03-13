// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:typed_data';

import 'dart:html' as html;

Future<String> savePng(Uint8List bytes, String fileName) async {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final safeName = fileName.trim().isEmpty ? 'export.png' : fileName.trim();
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', safeName)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);
  return safeName;
}
