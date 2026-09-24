import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Activates Firebase App Check (Zero-Trust client attestation).
class AppCheckService {
  AppCheckService._();

  static const String _recaptchaSiteKey = String.fromEnvironment(
    'RECAPTCHA_V3_SITE_KEY',
    defaultValue: '',
  );

  /// Best-effort activation. Debug builds use debug providers so local
  /// `flutter run` works after you register the debug token in Firebase Console.
  static Future<void> activate() async {
    try {
      if (kIsWeb) {
        if (_recaptchaSiteKey.isEmpty) {
          debugPrint(
            'App Check: set --dart-define=RECAPTCHA_V3_SITE_KEY=... for web attestation.',
          );
          return;
        }
        await FirebaseAppCheck.instance.activate(
          webProvider: ReCaptchaV3Provider(_recaptchaSiteKey),
        );
      } else {
        await FirebaseAppCheck.instance.activate(
          androidProvider:
              kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
          appleProvider:
              kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
        );
      }
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    } catch (e) {
      debugPrint('App Check activate failed: $e');
    }
  }
}
