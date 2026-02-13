import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text(
          'Notifications',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Text(
          'Your notifications will appear here.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.mediumGray,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
