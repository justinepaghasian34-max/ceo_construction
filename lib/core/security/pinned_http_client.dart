import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// HTTPS Dio client hardened against MitM proxies (Burp/ZAP) on mobile.
///
/// - Release mobile: rejects invalid certs (`badCertificateCallback = false`).
/// - Optional SPKI/leaf SHA-256 pins via `--dart-define=PIN_OPEN_METEO=...`
///   and `--dart-define=PIN_OSM=...` (hex). When set, only matching certs pass.
/// - Debug builds: system TLS only (allows local proxy testing).
/// - Web: standard Dio (browser owns TLS / CSP).
class PinnedHttpClient {
  PinnedHttpClient._();

  static const String _pinOpenMeteo = String.fromEnvironment(
    'PIN_OPEN_METEO',
    defaultValue: '',
  );
  static const String _pinOsm = String.fromEnvironment(
    'PIN_OSM',
    defaultValue: '',
  );

  static Dio create({Duration timeout = const Duration(seconds: 20)}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
      ),
    );

    if (kIsWeb) return dio;

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        if (kReleaseMode) {
          client.badCertificateCallback = (cert, host, port) => false;
        }
        return client;
      },
      validateCertificate: (cert, host, port) {
        if (cert == null) return false;
        final pin = _pinForHost(host);
        if (pin.isEmpty) return true; // system PKI
        final fingerprint = sha256.convert(cert.der).toString();
        return fingerprint.toLowerCase() == pin.toLowerCase();
      },
    );

    return dio;
  }

  static String _pinForHost(String host) {
    final h = host.toLowerCase();
    if (h.contains('open-meteo.com') && _pinOpenMeteo.isNotEmpty) {
      return _pinOpenMeteo;
    }
    if (h.contains('openstreetmap.org') && _pinOsm.isNotEmpty) {
      return _pinOsm;
    }
    return '';
  }
}
