import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform-backed secret store (Keystore / Keychain / Web crypto wrapper).
/// Used for Hive encryption keys and ephemeral OTP session flags.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _hiveKeyName = 'hive_aes_key_v1';
  static const _otpPrefix = 'otp_session_';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// 32-byte AES key for HiveAesCipher (created once per install).
  Future<Uint8List> getOrCreateHiveKey() async {
    final existing = await _storage.read(key: _hiveKeyName);
    if (existing != null && existing.isNotEmpty) {
      final bytes = base64Decode(existing);
      if (bytes.length == 32) return Uint8List.fromList(bytes);
    }
    final random = Random.secure();
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _storage.write(key: _hiveKeyName, value: base64Encode(key));
    return key;
  }

  Future<void> setOtpSessionVerified(String uid, bool verified) async {
    if (uid.isEmpty) return;
    await _storage.write(
      key: '$_otpPrefix$uid',
      value: verified ? '1' : '0',
    );
  }

  Future<bool> isOtpSessionVerified(String uid) async {
    if (uid.isEmpty) return false;
    final v = await _storage.read(key: '$_otpPrefix$uid');
    return v == '1';
  }

  Future<void> clearOtpSession(String uid) async {
    if (uid.isEmpty) return;
    await _storage.delete(key: '$_otpPrefix$uid');
  }

  Future<void> clearAllSessionFlags() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_otpPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('SecureStorage clearAllSessionFlags: $e');
      }
    }
  }
}
