import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/archive_service.dart';
import '../../../services/firebase_service.dart';
import 'admin_glass_layout.dart';

class ProgressBillingPanel extends StatefulWidget {
  const ProgressBillingPanel({super.key});

  @override
  State<ProgressBillingPanel> createState() => _ProgressBillingPanelState();
}

class _ProgressBillingPanelState extends State<ProgressBillingPanel> {
  /// Engineer group keys expanded by the admin (default: collapsed).
  final Set<String> _expandedEngineers = <String>{};

  String _engineerGroupKey(Map<String, dynamic> data) {
    final id = (data['siteManagerId'] ?? '').toString().trim();
    final name = (data['siteManagerName'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'id:$id';
    if (name.isNotEmpty) return 'name:${name.toLowerCase()}';
    return 'unassigned';
  }

  String _engineerGroupLabel(Map<String, dynamic> data) {
    final name = (data['siteManagerName'] ?? '').toString().trim();
    return name.isEmpty ? 'Unassigned' : name;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.projectsCollection.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Could not load progress billing.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.errorRed,
                ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
          return !ArchiveService.isArchived(data);
        }).toList();

        final groups = <String, List<QueryDocumentSnapshot>>{};
        final labels = <String, String>{};
        for (final doc in docs) {
          final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
          final key = _engineerGroupKey(data);
          groups.putIfAbsent(key, () => <QueryDocumentSnapshot>[]).add(doc);
          labels[key] = _engineerGroupLabel(data);
        }

        final sortedKeys = groups.keys.toList()
          ..sort((a, b) {
            if (a == 'unassigned') return 1;
            if (b == 'unassigned') return -1;
            return (labels[a] ?? a)
                .toLowerCase()
                .compareTo((labels[b] ?? b).toLowerCase());
          });
        for (final key in sortedKeys) {
          groups[key]!.sort((a, b) {
            final an = (((a.data() as Map?)?['name']) ?? '').toString();
            final bn = (((b.data() as Map?)?['name']) ?? '').toString();
            return an.toLowerCase().compareTo(bn.toLowerCase());
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Progress billing (1st / 2nd / 3rd)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Grouped by Resident Engineer — tap an engineer to show or hide projects. Record each billing against the approved budget.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                  ),
            ),
            const SizedBox(height: 14),
            if (docs.isEmpty)
              Text(
                'No projects yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
              )
            else
              for (final key in sortedKeys)
                _EngineerBillingGroup(
                  groupKey: key,
                  label: labels[key] ?? 'Unassigned',
                  projects: groups[key]!,
                  expanded: _expandedEngineers.contains(key),
                  onToggle: () {
                    setState(() {
                      if (_expandedEngineers.contains(key)) {
                        _expandedEngineers.remove(key);
                      } else {
                        _expandedEngineers.add(key);
                      }
                    });
                  },
                ),
          ],
        );
      },
    );
  }
}

class _EngineerBillingGroup extends StatelessWidget {
  const _EngineerBillingGroup({
    required this.groupKey,
    required this.label,
    required this.projects,
    required this.expanded,
    required this.onToggle,
  });

  final String groupKey;
  final String label;
  final List<QueryDocumentSnapshot> projects;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final unassigned = groupKey == 'unassigned';
    final count = projects.length;
    var totalBudget = 0.0;
    for (final doc in projects) {
      final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
      totalBudget += _asMoney(data['approvedBudget'] ?? data['contractAmount']);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: unassigned
                            ? AppTheme.mediumGray.withValues(alpha: 0.12)
                            : AppTheme.deepBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        unassigned
                            ? Icons.person_off_outlined
                            : Icons.engineering_outlined,
                        color: unassigned
                            ? AppTheme.mediumGray
                            : AppTheme.deepBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            count == 1
                                ? '1 project · ${_peso(totalBudget)} budget'
                                : '$count projects · ${_peso(totalBudget)} budget',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2DD4BF).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.mediumGray,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 10),
              for (final doc in projects)
                _ProjectBillingCard(
                  projectId: doc.id,
                  data: (doc.data() as Map?)?.cast<String, dynamic>() ?? {},
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectBillingCard extends StatelessWidget {
  const _ProjectBillingCard({
    required this.projectId,
    required this.data,
  });

  final String projectId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Untitled project').toString();
    final budget = _asMoney(data['approvedBudget'] ?? data['contractAmount']);
    final billings = _readBillings(data);
    final billedTotal = _asMoney(billings['first']!['amount']) +
        _asMoney(billings['second']!['amount']) +
        _asMoney(billings['third']!['amount']);
    final remaining = budget - billedTotal;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              _BudgetBadge(label: 'Budget', value: _peso(budget)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.receipt_long_outlined,
                label: 'Billed ${_peso(billedTotal)}',
                color: AppTheme.deepBlue,
              ),
              _MetaChip(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Left ${_peso(remaining)}',
                color: remaining >= 0 ? AppTheme.softGreen : AppTheme.errorRed,
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              final slots = <Widget>[
                _BillingSlot(
                  label: '1st',
                  billing: billings['first']!,
                  onEdit: () => _editBilling(
                    context,
                    slot: 'first',
                    title: '1st billing',
                    current: billings['first']!,
                  ),
                ),
                _BillingSlot(
                  label: '2nd',
                  billing: billings['second']!,
                  onEdit: () => _editBilling(
                    context,
                    slot: 'second',
                    title: '2nd billing',
                    current: billings['second']!,
                  ),
                ),
                _BillingSlot(
                  label: '3rd',
                  billing: billings['third']!,
                  onEdit: () => _editBilling(
                    context,
                    slot: 'third',
                    title: '3rd billing',
                    current: billings['third']!,
                  ),
                ),
              ];

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < slots.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: slots[i]),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < slots.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    slots[i],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editBilling(
    BuildContext context, {
    required String slot,
    required String title,
    required Map<String, dynamic> current,
  }) async {
    final amountController = TextEditingController(
      text: _asMoney(current['amount']) > 0
          ? _asMoney(current['amount']).toStringAsFixed(2)
          : '',
    );
    final notesController = TextEditingController(
      text: (current['notes'] ?? '').toString(),
    );
    DateTime? date = current['date'] is DateTime
        ? current['date'] as DateTime
        : DateTime.tryParse((current['date'] ?? '').toString());
    var paid = current['paid'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('$title — ${(data['name'] ?? '').toString()}'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Billing amount (₱)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        date == null
                            ? 'Billing date'
                            : DateFormat.yMMMd().format(date!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setLocal(() => date = picked);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Marked as paid / released'),
                      value: paid,
                      onChanged: (v) => setLocal(() => paid = v),
                    ),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;

    final amount = _asMoney(amountController.text);
    final billings = _readBillings(data);
    billings[slot] = {
      'amount': amount,
      'date': date?.toIso8601String(),
      'paid': paid,
      'notes': notesController.text.trim(),
    };

    await FirebaseService.instance.projectsCollection.doc(projectId).update({
      'progressBillings': {
        'first': billings['first'],
        'second': billings['second'],
        'third': billings['third'],
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class _BudgetBadge extends StatelessWidget {
  const _BudgetBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.deepBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.deepBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.mediumGray,
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.deepBlue,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _BillingSlot extends StatelessWidget {
  const _BillingSlot({
    required this.label,
    required this.billing,
    required this.onEdit,
  });

  final String label;
  final Map<String, dynamic> billing;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final amount = _asMoney(billing['amount']);
    final paid = billing['paid'] == true;
    final hasAmount = amount > 0;
    final date = billing['date'] is DateTime
        ? billing['date'] as DateTime
        : DateTime.tryParse((billing['date'] ?? '').toString());
    final dateText =
        date == null ? 'No date' : DateFormat.yMMMd().format(date);
    final statusColor = !hasAmount
        ? AppTheme.mediumGray
        : paid
            ? AppTheme.softGreen
            : AppTheme.warningOrange;

    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$label billing',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: AppTheme.mediumGray.withValues(alpha: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasAmount ? _peso(amount) : '—',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: hasAmount ? AppTheme.darkGray : AppTheme.mediumGray,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      !hasAmount
                          ? 'Not set'
                          : paid
                              ? 'Paid · $dateText'
                              : 'Unpaid · $dateText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, Map<String, dynamic>> _readBillings(Map<String, dynamic> data) {
  Map<String, dynamic> slot(String key, String amountKey) {
    final nested = data['progressBillings'];
    if (nested is Map && nested[key] is Map) {
      return Map<String, dynamic>.from(nested[key] as Map);
    }
    return {
      'amount': _asMoney(data[amountKey]),
      'date': data['${key}BillingDate'],
      'paid': data['${key}BillingPaid'] == true,
      'notes': '',
    };
  }

  return {
    'first': slot('first', 'firstBillingAmount'),
    'second': slot('second', 'secondBillingAmount'),
    'third': slot('third', 'thirdBillingAmount'),
  };
}

double _asMoney(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(
          value.replaceAll(',', '').replaceAll('₱', '').trim(),
        ) ??
        0;
  }
  return 0;
}

String _peso(double value) {
  final digits = value.toStringAsFixed(2);
  final parts = digits.split('.');
  final buffer = StringBuffer();
  var count = 0;
  for (var i = parts[0].length - 1; i >= 0; i--) {
    buffer.write(parts[0][i]);
    count++;
    if (count == 3 && i != 0) {
      buffer.write(',');
      count = 0;
    }
  }
  return '₱${buffer.toString().split('').reversed.join()}.${parts[1]}';
}
