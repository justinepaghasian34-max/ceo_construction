import 'dart:typed_data';

import 'png_exporter_stub.dart'
    if (dart.library.html) 'png_exporter_web.dart'
    if (dart.library.io) 'png_exporter_io.dart' as impl;

Future<String> savePng(Uint8List bytes, String fileName) {
  return impl.savePng(bytes, fileName);
}
