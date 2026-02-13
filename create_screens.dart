// Script to create all missing screen files
// Run this with: dart create_screens.dart

import 'dart:io';

void main() {
  final screens = [
    // Admin screens
    'lib/views/admin/admin_projects.dart',
    'lib/views/admin/admin_payroll.dart', 
    'lib/views/admin/admin_analytics.dart',
    'lib/views/admin/admin_history.dart',
    
    // Accounting screens
    'lib/views/accounting/accounting_home.dart',
    'lib/views/accounting/accounting_payroll.dart',
    
    // Treasury screens
    'lib/views/treasury/treasury_home.dart',
    'lib/views/treasury/treasury_payroll.dart',
    'lib/views/treasury/treasury_disbursements.dart',
    
    // CEO screens
    'lib/views/ceo/ceo_home.dart',
    'lib/views/ceo/ceo_dashboard.dart',
    'lib/views/ceo/ceo_analytics.dart',
    'lib/views/ceo/ceo_reports.dart',
    
    // Common screens
    'lib/views/common/profile_screen.dart',
    'lib/views/common/settings_screen.dart',
    'lib/views/common/notifications_screen.dart',
  ];

  for (final screenPath in screens) {
    createScreen(screenPath);
  }
  
  stdout.writeln('Created ${screens.length} screen files!');
}

void createScreen(String path) {
  final file = File(path);
  final className = getClassName(path);
  final title = getTitle(path);
  
  // Create directory if it doesn't exist
  file.parent.createSync(recursive: true);
  
  final content = '''import 'package:flutter/material.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('$title')),
      body: const Center(child: Text('$title - Coming Soon')),
    );
  }
}''';

  file.writeAsStringSync(content);
  stdout.writeln('Created: $path');
}

String getClassName(String path) {
  final filename = path.split('/').last.replaceAll('.dart', '');
  return filename.split('_').map((word) => 
    word[0].toUpperCase() + word.substring(1)).join('');
}

String getTitle(String path) {
  final filename = path.split('/').last.replaceAll('.dart', '');
  return filename.split('_').map((word) => 
    word[0].toUpperCase() + word.substring(1)).join(' ');
}
