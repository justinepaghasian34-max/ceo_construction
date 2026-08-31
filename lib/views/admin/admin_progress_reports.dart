import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firebase_service.dart';
import '../../utils/png_exporter.dart';
import '../../widgets/common/storage_network_image.dart';

class AdminProgressReportsScreen extends StatelessWidget {
  const AdminProgressReportsScreen({super.key});

  List<_ImageEntry> _extractImageEntries(Map<String, dynamic> data) {
    final baseFileName =
        (data['fileName'] ?? data['file_name'] ?? '').toString().trim();
    final sources = ProgressReportImages.extract(data);
    return [
      for (var i = 0; i < sources.length; i++)
        _ImageEntry(
          source: sources[i],
          label: baseFileName.isNotEmpty
              ? (sources.length == 1
                  ? baseFileName
                  : '$baseFileName ${i + 1}')
              : 'Site photo ${i + 1}',
        ),
    ];
  }

  String _engineerLabel(String name, String email) {
    if (name.isEmpty && email.isEmpty) return '';
    if (name.isEmpty || name.toLowerCase() == email.toLowerCase()) {
      return email.isEmpty ? name : email;
    }
    if (email.isEmpty) return name;
    return '$name ($email)';
  }

  void _showImageViewer(BuildContext context, String url, String label) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 860,
            height: 640,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppTheme.lightGray,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 6,
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: StorageNetworkImage(
                        source: url,
                        fit: BoxFit.contain,
                        errorIconColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseService.instance.aiAnalysisCollection.where(
      'kind',
      whereIn: const <String>[
        'govtrack_progress_report',
        'govtrack_image_progress_submit',
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress Reports'),
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
                'Failed to load progress reports: ${snapshot.error}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = (snapshot.data?.docs ?? const []).toList()
            ..sort((a, b) {
              final ad = (a.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final bd = (b.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
              final at = ad['createdAt'];
              final bt = bd['createdAt'];

              DateTime? aDate;
              if (at is Timestamp) aDate = at.toDate();
              if (at is DateTime) aDate = at;
              DateTime? bDate;
              if (bt is Timestamp) bDate = bt.toDate();
              if (bt is DateTime) bDate = bt;

              final aMillis = aDate?.millisecondsSinceEpoch ?? 0;
              final bMillis = bDate?.millisecondsSinceEpoch ?? 0;
              return bMillis.compareTo(aMillis);
            });
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No progress reports yet.',
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

              final projectName =
                  (data['projectName'] ?? 'Unknown Project').toString();
              final progressPercent = data['progressPercent'];
              final assignedName =
                  (data['assignedSiteManagerName'] ?? '').toString().trim();
              final assignedEmail =
                  (data['assignedSiteManagerEmail'] ?? '').toString().trim();

              final submittedBy =
                  (data['submittedByName'] ?? '').toString().trim();

              final createdAt = data['createdAt'];
              final createdAtText = _formatTimestamp(createdAt);

              final pctText = (progressPercent is num)
                  ? '${progressPercent.toStringAsFixed(1)}%'
                  : '—';

              final imageEntries = _extractImageEntries(data);
              final coverUrl =
                  imageEntries.isNotEmpty ? imageEntries.first.source : '';
              final engineer =
                  _engineerLabel(assignedName, assignedEmail);

              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _showDetails(context, data, doc.id),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Material(
                          elevation: 3,
                          shadowColor: Colors.black26,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: Container(
                            width: 92,
                            height: 92,
                            color: AppTheme.lightGray,
                            child: coverUrl.isEmpty
                                ? Container(
                                    color: AppTheme.deepBlue
                                        .withValues(alpha: 0.08),
                                    alignment: Alignment.center,
                                    child: Text(
                                      (progressPercent is num)
                                          ? progressPercent.round().toString()
                                          : '—',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppTheme.deepBlue,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  )
                                : StorageNetworkImage(
                                    source: coverUrl,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                projectName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Progress: $pctText',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: AppTheme.mediumGray,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              if (engineer.isNotEmpty)
                                Text(
                                  'Assigned Resident Engineer: $engineer',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                              if (submittedBy.isNotEmpty)
                                Text(
                                  'Submitted by: $submittedBy',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                              if (createdAtText.isNotEmpty)
                                Text(
                                  createdAtText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                              if (imageEntries.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 68,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: imageEntries.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemBuilder: (context, i) {
                                      final entry = imageEntries[i];
                                      return Material(
                                        elevation: 4,
                                        shadowColor: Colors.black26,
                                        borderRadius: BorderRadius.circular(12),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () => _showImageViewer(
                                              context,
                                              entry.source,
                                              entry.label),
                                          child: SizedBox(
                                            width: 64,
                                            height: 64,
                                            child: Tooltip(
                                              message: entry.label,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  StorageNetworkImage(
                                                    source: entry.source,
                                                    fit: BoxFit.cover,
                                                    semanticLabel: entry.label,
                                                  ),
                                                  Positioned(
                                                    right: 4,
                                                    bottom: 4,
                                                    child: Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 6,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                                alpha: 0.55),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      child: Text(
                                                        '${i + 1}',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: AppTheme.mediumGray),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    DateTime? date;
    if (ts is Timestamp) {
      date = ts.toDate();
    } else if (ts is DateTime) {
      date = ts;
    }
    if (date == null) return '';
    final d = date;
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd $hh:$min';
  }

  void _showDetails(
      BuildContext context, Map<String, dynamic> data, String id) {
    final exportKey = GlobalKey();

    final projectName = (data['projectName'] ?? 'Unknown Project').toString();
    final projectId = (data['projectId'] ?? '').toString();

    final progressPercent = data['progressPercent'];
    final pctText = (progressPercent is num)
        ? '${progressPercent.toStringAsFixed(1)}%'
        : '—';

    final assignedName =
        (data['assignedSiteManagerName'] ?? '').toString().trim();
    final assignedEmail =
        (data['assignedSiteManagerEmail'] ?? '').toString().trim();

    final submittedByName = (data['submittedByName'] ?? '').toString().trim();
    final submittedByEmail = (data['submittedByEmail'] ?? '').toString().trim();

    final analysis = (data['analysis'] as Map?)?.cast<String, dynamic>();
    final summary = (analysis?['summary'] ?? '').toString().trim();
    final schedule = (analysis?['schedule'] as Map?)?.cast<String, dynamic>();
    final status =
        schedule == null ? null : schedule['status']?.toString().trim();

    final imageEntries = _extractImageEntries(data);

    Future<void> exportPng() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final boundary = exportKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Export failed: UI not ready.')),
          );
          return;
        }

        final image = await boundary.toImage(pixelRatio: 3);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = byteData?.buffer.asUint8List();
        if (bytes == null || bytes.isEmpty) {
          if (!messenger.mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Export failed: empty image.')),
          );
          return;
        }

        final safeProject = projectName
            .replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '')
            .trim()
            .replaceAll(' ', '_');
        final fileName =
            'progress_report_${safeProject.isEmpty ? 'project' : safeProject}_$id.png';
        final result = await savePng(bytes, fileName);
        if (!messenger.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Exported PNG: $result')),
        );
      } catch (e) {
        if (!messenger.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(projectName),
          content: SizedBox(
            width: 520,
            child: RepaintBoundary(
              key: exportKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kv(context, 'Progress', pctText),
                    if (projectId.isNotEmpty)
                      _kv(context, 'Project ID', projectId),
                    if (imageEntries.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Images',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in imageEntries)
                            InkWell(
                              onTap: () => _showImageViewer(
                                  context, entry.source, entry.label),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 140,
                                      height: 92,
                                      color: AppTheme.lightGray,
                                      child: StorageNetworkImage(
                                        source: entry.source,
                                        fit: BoxFit.cover,
                                        semanticLabel: entry.label,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      entry.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.mediumGray,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                    _kv(
                      context,
                      'Assigned Resident Engineer',
                      _engineerLabel(assignedName, assignedEmail).isEmpty
                          ? '—'
                          : _engineerLabel(assignedName, assignedEmail),
                    ),
                    if (data['fileName'] != null ||
                        data['file_name'] != null) ...[
                      _kv(
                        context,
                        'Image file name',
                        (data['fileName'] ?? data['file_name'] ?? '')
                            .toString(),
                      ),
                    ],
                    _kv(
                      context,
                      'Submitted by',
                      submittedByName.isEmpty
                          ? '—'
                          : (submittedByEmail.isEmpty
                              ? submittedByName
                              : '$submittedByName ($submittedByEmail)'),
                    ),
                    _kv(context, 'Record ID', id),
                    if (status != null && status.isNotEmpty)
                      _kv(context, 'Schedule Status', status),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'AI Summary',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: exportPng,
              child: const Text('Export as PNG'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageEntry {
  const _ImageEntry({
    required this.source,
    required this.label,
  });

  final String source;
  final String label;
}
