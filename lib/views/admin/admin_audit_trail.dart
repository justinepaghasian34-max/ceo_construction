import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/app_card.dart';
import '../../services/audit_log_service.dart';

class AdminAuditTrail extends StatefulWidget {
  const AdminAuditTrail({super.key});

  @override
  State<AdminAuditTrail> createState() => _AdminAuditTrailState();
}

class _AdminAuditTrailState extends State<AdminAuditTrail> {
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    AuditLogService.instance.logAction(action: 'admin_view_audit_trail');
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('audit_logs')
        .orderBy('timestamp', descending: true);

    if (_startDate != null) {
      final startOfDay = DateTime(
        _startDate!.year,
        _startDate!.month,
        _startDate!.day,
      );
      query = query.where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
      );
    }

    if (_endDate != null) {
      final endOfDay = DateTime(
        _endDate!.year,
        _endDate!.month,
        _endDate!.day,
        23,
        59,
        59,
        999,
      );
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
      );
    }

    query = query.limit(200);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Audit Trail',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter by date',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final initial = _startDate ?? _endDate ?? now;
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (picked != null) {
                              setState(() {
                                _startDate = picked;
                                if (_endDate != null &&
                                    _endDate!.isBefore(picked)) {
                                  _endDate = picked;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            _startDate == null
                                ? 'From date'
                                : '${_startDate!.year.toString().padLeft(4, '0')}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final initial = _endDate ?? _startDate ?? now;
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(now.year + 5),
                            );
                            if (picked != null) {
                              setState(() {
                                _endDate = picked;
                                if (_startDate != null &&
                                    _startDate!.isAfter(picked)) {
                                  _startDate = picked;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            _endDate == null
                                ? 'To date'
                                : '${_endDate!.year.toString().padLeft(4, '0')}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Clear filters',
                        onPressed: _startDate == null && _endDate == null
                            ? null
                            : () {
                                setState(() {
                                  _startDate = null;
                                  _endDate = null;
                                });
                              },
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load audit logs.',
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
                      'No audit entries for the selected dates.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final action = (data['action'] ?? 'unknown_action')
                        .toString();
                    final userEmail = (data['userEmail'] ?? 'Unknown user')
                        .toString();
                    final userRole = (data['userRole'] ?? '').toString();
                    final projectId = (data['projectId'] ?? '').toString();
                    final ipAddress = (data['ipAddress'] ?? '').toString();

                    final timestampRaw = data['timestamp'];
                    DateTime? timestamp;
                    if (timestampRaw is Timestamp) {
                      timestamp = timestampRaw.toDate();
                    } else if (timestampRaw is String) {
                      timestamp = DateTime.tryParse(timestampRaw);
                    }

                    String timeText = '';
                    if (timestamp != null) {
                      timeText =
                          '${timestamp.year.toString().padLeft(4, '0')}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
                          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
                    }

                    final detailsRaw = data['details'];
                    Map<String, dynamic> details = {};
                    if (detailsRaw is Map) {
                      details = detailsRaw.map(
                        (key, value) => MapEntry(key.toString(), value),
                      );
                    }

                    String? detailsText;
                    if (details.isNotEmpty) {
                      final parts = <String>[];
                      details.forEach((k, v) {
                        parts.add('$k: $v');
                      });
                      detailsText = parts.join(' • ');
                    }

                    final roleLabel = userRole.isNotEmpty ? ' ($userRole)' : '';

                    return AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$userEmail$roleLabel',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (projectId.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Project: $projectId',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.mediumGray),
                            ),
                          ],
                          if (detailsText != null &&
                              detailsText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              detailsText,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.mediumGray),
                            ),
                          ],
                          if (ipAddress.isNotEmpty || timeText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (timeText.isNotEmpty) timeText,
                                if (ipAddress.isNotEmpty) 'IP: $ipAddress',
                              ].join('  •  '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.mediumGray),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
