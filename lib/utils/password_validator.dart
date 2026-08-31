/// Client-side password policy. Firebase Auth stores passwords with
/// scrypt hashing on the server — this never hashes or stores secrets locally.
String? validatePassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) {
    return 'Please enter a password';
  }
  if (password.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (password.length > 128) {
    return 'Password is too long';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Include at least one uppercase letter';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Include at least one lowercase letter';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Include at least one number';
  }
  if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;/]').hasMatch(password)) {
    return 'Include at least one special character';
  }

  const common = {
    'password',
    'password1',
    'password123',
    '123456',
    '12345678',
    'qwerty',
    'letmein',
    'admin123',
    'welcome',
    'iloveyou',
  };
  if (common.contains(password.toLowerCase())) {
    return 'This password is too common';
  }

  return null;
}
