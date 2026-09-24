import 'package:flutter/foundation.dart';

/// Defense-in-depth logging — silent in release so device logs do not leak
/// tokens, emails, or stack traces to Kali/ADB log dumps.
class SecureLog {
  SecureLog._();

  static void d(String message, {String? tag}) {
    if (kReleaseMode) return;
    debugPrint(tag == null ? message : '[$tag] $message');
  }

  static void e(Object error, [StackTrace? stack, String? tag]) {
    if (kReleaseMode) return;
    final prefix = tag == null ? 'ERROR' : 'ERROR:$tag';
    debugPrint('$prefix: $error');
    if (stack != null) debugPrint('$stack');
  }
}
