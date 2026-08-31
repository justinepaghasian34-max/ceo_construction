import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  DateTime _parseCreatedAt(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatWhen(dynamic value) {
    final date = _parseCreatedAt(value);
    if (date.millisecondsSinceEpoch == 0) return '';
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd $hh:$min';
  }

  bool _visibleToUser(
    Map<String, dynamic> data, {
    required bool isAdmin,
    required bool isCeo,
    String? uid,
  }) {
    if (isAdmin || isCeo) return true;
    if (uid == null || uid.isEmpty) return false;
    return (data['userId'] ?? '').toString() == uid;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'progress_report_submitted':
        return Icons.photo_camera_outlined;
      case 'material_request':
      case 'low_materials':
        return Icons.inventory_2_outlined;
      case 'weather_rain_alert':
        return Icons.thunderstorm_outlined;
      case 'daily_report_submitted':
        return Icons.assignment_outlined;
      case 'payroll_validated':
      case 'payroll_paid':
      case 'payroll_validation_completed':
        return Icons.payments_outlined;
      case 'ai_delay_detected':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final uid = AuthService.instance.currentFirebaseUser?.uid;
    final isAdmin = user?.isAdmin == true;
    final isCeo = user?.role == AppConstants.roleCeo ||
        user?.role == 'ceo_head';

    final stream = uid == null
        ? const Stream<QuerySnapshot>.empty()
        : FirebaseService.instance.notificationsCollection
            .limit(400)
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text(
          'Notifications',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load notifications: ${snapshot.error}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.errorRed,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rawDocs = snapshot.data?.docs ?? [];
          final docs = rawDocs.where((d) {
            final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            return _visibleToUser(
              data,
              isAdmin: isAdmin,
              isCeo: isCeo,
              uid: uid,
            );
          }).toList()
            ..sort((a, b) {
              final ad = (a.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final bd = (b.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              return _parseCreatedAt(bd['createdAt'])
                  .compareTo(_parseCreatedAt(ad['createdAt']));
            });
          if (docs.isEmpty) {
            return Center(
              child: Text(
                isAdmin || isCeo
                    ? 'No site or mobile notifications yet.'
                    : 'No notifications yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final title = (data['title'] ?? 'Notification').toString();
              final message = (data['message'] ?? '').toString();
              final isRead =
                  (data['isRead'] ?? data['read'] ?? false) == true;
              final projectName = (data['projectName'] ?? '').toString();
              final type = (data['type'] ?? '').toString();
              final when = _formatWhen(data['createdAt']);

              return InkWell(
                onTap: () async {
                  try {
                    await doc.reference.update({'isRead': true});
                  } catch (_) {}
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : const Color(0xFFF3F7FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.deepBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _iconForType(type),
                          color: AppTheme.deepBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.deepBlue,
                                  ),
                            ),
                            if (projectName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                projectName,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                            if (message.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                message,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.black87,
                                    ),
                              ),
                            ],
                            if (when.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                when,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppTheme.mediumGray,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
