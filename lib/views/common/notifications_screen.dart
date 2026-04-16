import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final uid = AuthService.instance.currentFirebaseUser?.uid;

    // Avoid composite index requirements by not combining where + orderBy.
    // We order by createdAt only (single-field index) and filter in Dart.
    final stream = uid == null
        ? const Stream<QuerySnapshot>.empty()
        : FirebaseService.instance.notificationsCollection
            .orderBy('createdAt', descending: true)
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
            if (user?.isAdmin == true) {
              return (data['audienceRole'] ?? '').toString() == 'admin';
            }
            return uid != null && (data['userId'] ?? '').toString() == uid;
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
                'No notifications yet.',
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
              final isRead = (data['isRead'] ?? false) == true;
              final projectName = (data['projectName'] ?? '').toString();

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.deepBlue,
                            ),
                      ),
                      if (projectName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          projectName,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          message,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.black87,
                                  ),
                        ),
                      ],
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
