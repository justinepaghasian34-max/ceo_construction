import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/app_card.dart';

class AdminHistory extends StatelessWidget {
  const AdminHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance.collectionGroup('history');

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Project History',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load history',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.errorRed,
                    ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No history entries yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = (data['title'] ?? data['type'] ?? 'History item').toString();
              final description = (data['description'] ?? '').toString();
              final createdAtString = data['createdAt'] as String?;
              DateTime? createdAt;
              if (createdAtString != null) {
                createdAt = DateTime.tryParse(createdAtString);
              }
              final timeText = createdAt != null
                  ? '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
                  : '';

              return AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.timeline,
                      color: AppTheme.deepBlue,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          if (description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                description,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                    ),
                              ),
                            ),
                          if (timeText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                timeText,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
