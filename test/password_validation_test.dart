import 'package:coecons/utils/password_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Password validation', () {
    test('rejects weak passwords', () {
      expect(validatePassword('123456'), isNotNull);
      expect(validatePassword('password'), isNotNull);
    });

    test('accepts strong passwords', () {
      expect(validatePassword('StrongPass1!'), isNull);
      expect(validatePassword('Ceo@2026Site'), isNull);
    });
  });
}
