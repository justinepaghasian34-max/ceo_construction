import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Text(
          'Application settings will be available here.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mediumGray,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
