import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
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
  String? _selectedUser;
  String? _selectedAction;
  bool _showExtraData = true;
  bool _showIp = true;
  bool _showGeo = true;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AuditLogService.instance.logAction(action: 'admin_view_audit_trail');
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _csvEscape(String s) {
    final needsQuotes = s.contains(',') || s.contains('\n') || s.contains('"');
    if (!needsQuotes) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            context.push(RouteNames.adminHome);
          },
        ),
        title: const Text(
          'Audit Trail',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

          final users = <String>{};
          final actions = <String>{};

          for (final d in docs) {
            final data = d.data();
            final userEmail = (data['userEmail'] ?? '').toString().trim();
            final action = (data['action'] ?? '').toString().trim();
            if (userEmail.isNotEmpty) users.add(userEmail);
            if (action.isNotEmpty) actions.add(action);
          }

          final sortedUsers = users.toList()..sort();
          final sortedActions = actions.toList()..sort();

          if (_selectedUser != null && _selectedUser!.isNotEmpty) {
            if (!users.contains(_selectedUser)) {
              _selectedUser = null;
            }
          }
          if (_selectedAction != null && _selectedAction!.isNotEmpty) {
            if (!actions.contains(_selectedAction)) {
              _selectedAction = null;
            }
          }

          final filtered = docs.where((d) {
            final data = d.data();
            final userEmail = (data['userEmail'] ?? '').toString();
            final action = (data['action'] ?? '').toString();
            if (_selectedUser != null && _selectedUser!.isNotEmpty) {
              if (userEmail != _selectedUser) return false;
            }
            if (_selectedAction != null && _selectedAction!.isNotEmpty) {
              if (action != _selectedAction) return false;
            }
            return true;
          }).toList();

          String rangeText;
          if (_startDate == null && _endDate == null) {
            rangeText = 'Choose date range';
          } else if (_startDate != null && _endDate != null) {
            rangeText = '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}';
          } else if (_startDate != null) {
            rangeText = 'From ${_formatDate(_startDate!)}';
          } else {
            rangeText = 'To ${_formatDate(_endDate!)}';
          }

          Future<void> copyCsv() async {
            final messenger = ScaffoldMessenger.of(context);

            final headers = <String>[
              'User',
              'Date & Time',
              'Action',
              if (_showExtraData) 'Extra Data',
              if (_showIp) 'IP',
              if (_showGeo) 'Geo Location',
            ];

            final lines = <String>[];
            lines.add(headers.map(_csvEscape).join(','));

            for (final d in filtered) {
              final data = d.data();
              final userEmail = (data['userEmail'] ?? '').toString();
              final action = (data['action'] ?? '').toString();

              final timestampRaw = data['timestamp'];
              DateTime? timestamp;
              if (timestampRaw is Timestamp) {
                timestamp = timestampRaw.toDate();
              } else if (timestampRaw is String) {
                timestamp = DateTime.tryParse(timestampRaw);
              }
              final timeText = timestamp == null ? '' : _formatDateTime(timestamp);

              final detailsRaw = data['details'];
              Map<String, dynamic> details = {};
              if (detailsRaw is Map) {
                details = detailsRaw.map(
                  (key, value) => MapEntry(key.toString(), value),
                );
              }
              String detailsText = '';
              if (details.isNotEmpty) {
                final parts = <String>[];
                details.forEach((k, v) {
                  parts.add('$k: $v');
                });
                detailsText = parts.join(' • ');
              }

              final ipAddress = (data['ipAddress'] ?? '').toString();
              final geo = (data['geoLocation'] ?? '').toString();

              final row = <String>[
                userEmail,
                timeText,
                action,
                if (_showExtraData) detailsText,
                if (_showIp) ipAddress,
                if (_showGeo) geo,
              ];
              lines.add(row.map(_csvEscape).join(','));
            }

            final csv = lines.join('\n');
            await Clipboard.setData(ClipboardData(text: csv));
            messenger.showSnackBar(
              const SnackBar(content: Text('CSV copied to clipboard')),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 900;

                      final userField = DropdownButtonFormField<String>(
                        initialValue: _selectedUser,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Filter by user'),
                          ),
                          ...sortedUsers.map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(
                                u,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedUser = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      );

                      final actionField = DropdownButtonFormField<String>(
                        initialValue: _selectedAction,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Filter by action'),
                          ),
                          ...sortedActions.map(
                            (a) => DropdownMenuItem(
                              value: a,
                              child: Text(
                                a,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedAction = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      );

                      final dateField = OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final initialStart = _startDate ?? now;
                          final initialEnd = _endDate ?? _startDate ?? now;
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(now.year + 5),
                            initialDateRange: DateTimeRange(
                              start: initialStart,
                              end: initialEnd,
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked.start;
                              _endDate = picked.end;
                            });
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          rangeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );

                      final csvButton = ElevatedButton(
                        onPressed: filtered.isEmpty ? null : copyCsv,
                        child: const Text('CSV'),
                      );

                      final columnsButton = OutlinedButton(
                        onPressed: () async {
                          final currentExtra = _showExtraData;
                          final currentIp = _showIp;
                          final currentGeo = _showGeo;

                          final result = await showDialog<Map<String, bool>>(
                            context: context,
                            builder: (dialogContext) {
                              bool showExtra = currentExtra;
                              bool showIp = currentIp;
                              bool showGeo = currentGeo;

                              return AlertDialog(
                                title: const Text('Columns'),
                                content: StatefulBuilder(
                                  builder: (context, setDialogState) {
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CheckboxListTile(
                                          value: showExtra,
                                          onChanged: (v) => setDialogState(
                                            () => showExtra = v ?? true,
                                          ),
                                          title: const Text('Extra Data'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        CheckboxListTile(
                                          value: showIp,
                                          onChanged: (v) => setDialogState(
                                            () => showIp = v ?? true,
                                          ),
                                          title: const Text('IP'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        CheckboxListTile(
                                          value: showGeo,
                                          onChanged: (v) => setDialogState(
                                            () => showGeo = v ?? true,
                                          ),
                                          title: const Text('Geo Location'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(dialogContext)
                                        .pop(<String, bool>{
                                      'extra': currentExtra,
                                      'ip': currentIp,
                                      'geo': currentGeo,
                                    }),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(dialogContext)
                                        .pop(<String, bool>{
                                      'extra': showExtra,
                                      'ip': showIp,
                                      'geo': showGeo,
                                    }),
                                    child: const Text('Apply'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (result != null) {
                            setState(() {
                              _showExtraData = result['extra'] ?? true;
                              _showIp = result['ip'] ?? true;
                              _showGeo = result['geo'] ?? true;
                            });
                          }
                        },
                        child: const Text('Columns'),
                      );

                      final clearButton = IconButton(
                        tooltip: 'Clear filters',
                        onPressed: (_startDate == null &&
                                    _endDate == null &&
                                    _selectedUser == null &&
                                    _selectedAction == null)
                                ? null
                                : () {
                                    setState(() {
                                      _startDate = null;
                                      _endDate = null;
                                      _selectedUser = null;
                                      _selectedAction = null;
                                    });
                                  },
                        icon: const Icon(Icons.clear),
                      );

                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            userField,
                            const SizedBox(height: 10),
                            actionField,
                            const SizedBox(height: 10),
                            dateField,
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                csvButton,
                                const SizedBox(width: 8),
                                columnsButton,
                                const Spacer(),
                                clearButton,
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: userField),
                          const SizedBox(width: 12),
                          Expanded(child: actionField),
                          const SizedBox(width: 12),
                          Expanded(child: dateField),
                          const SizedBox(width: 12),
                          csvButton,
                          const SizedBox(width: 8),
                          columnsButton,
                          const SizedBox(width: 4),
                          clearButton,
                        ],
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppCard(
                    padding: const EdgeInsets.all(0),
                    child: Builder(
                      builder: (context) {
                        if (filtered.isEmpty) {
                          return Center(
                            child: Text(
                              'No audit entries for the selected filters.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppTheme.mediumGray),
                            ),
                          );
                        }

                        final columns = <DataColumn>[
                          const DataColumn(label: Text('User')),
                          const DataColumn(label: Text('Date & Time')),
                          const DataColumn(label: Text('Action')),
                          if (_showExtraData)
                            const DataColumn(label: Text('Extra Data')),
                          if (_showIp) const DataColumn(label: Text('IP')),
                          if (_showGeo)
                            const DataColumn(label: Text('Geo Location')),
                        ];

                        final rows = filtered.map((doc) {
                          final data = doc.data();

                          final userEmail =
                              (data['userEmail'] ?? 'Unknown user').toString();
                          final action =
                              (data['action'] ?? 'unknown_action').toString();

                          final timestampRaw = data['timestamp'];
                          DateTime? timestamp;
                          if (timestampRaw is Timestamp) {
                            timestamp = timestampRaw.toDate();
                          } else if (timestampRaw is String) {
                            timestamp = DateTime.tryParse(timestampRaw);
                          }
                          final timeText =
                              timestamp == null ? '' : _formatDateTime(timestamp);

                          final detailsRaw = data['details'];
                          Map<String, dynamic> details = {};
                          if (detailsRaw is Map) {
                            details = detailsRaw.map(
                              (key, value) => MapEntry(key.toString(), value),
                            );
                          }
                          String detailsText = '';
                          if (details.isNotEmpty) {
                            final parts = <String>[];
                            details.forEach((k, v) {
                              parts.add('$k: $v');
                            });
                            detailsText = parts.join(' • ');
                          }

                          final ipAddress = (data['ipAddress'] ?? '').toString();
                          final geo = (data['geoLocation'] ?? '').toString();

                          final cells = <DataCell>[
                            DataCell(
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  userEmail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(timeText)),
                            DataCell(
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Text(
                                  action,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (_showExtraData)
                              DataCell(
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 380),
                                  child: Text(
                                    detailsText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            if (_showIp)
                              DataCell(
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 180),
                                  child: Text(
                                    ipAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            if (_showGeo)
                              DataCell(
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 220),
                                  child: Text(
                                    geo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ];

                          return DataRow(cells: cells);
                        }).toList();

                        return Scrollbar(
                          controller: _verticalScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            controller: _verticalScrollController,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: _horizontalScrollController,
                              child: DataTable(
                                columns: columns,
                                rows: rows,
                                headingRowColor:
                                    WidgetStateProperty.all(Colors.white),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 72,
                                columnSpacing: 18,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
