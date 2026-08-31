import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firebase_service.dart';
import 'widgets/admin_glass_layout.dart';

class AdminProjectDetailsScreen extends StatelessWidget {
  const AdminProjectDetailsScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.instance.projectsCollection
          .doc(projectId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: _detailsAppBar(context, 'Project details'),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: _detailsAppBar(context, 'Project details'),
            body: const Center(child: Text('Project not found')),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: _detailsAppBar(
            context,
            (data['name'] ?? 'Project details').toString(),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: _ProjectDetailsBody(
                  projectId: projectId,
                  data: data,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _detailsAppBar(BuildContext context, String title) {
    return AppBar(
      backgroundColor: AppTheme.deepBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ProjectDetailsBody extends StatelessWidget {
  const _ProjectDetailsBody({
    required this.projectId,
    required this.data,
  });

  final String projectId;
  final Map<String, dynamic> data;

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final d = DateTime.parse(raw);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtBudget(dynamic raw) {
    if (raw is num) return '₱${raw.toStringAsFixed(2)}';
    if (raw is String && raw.isNotEmpty) return '₱$raw';
    return '—';
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ongoing':
        return AppTheme.softGreen;
      case 'completed':
        return AppTheme.primaryBlue;
      case 'pending':
        return AppTheme.warningOrange;
      default:
        return AppTheme.mediumGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? 'Untitled Project').toString();
    final status = (data['status'] ?? 'unknown').toString();
    final progress = (data['progressPercentage'] ?? 0).toDouble().clamp(0, 100);
    final projectCode = (data['projectCode'] ?? projectId).toString();
    final location = (data['location'] ?? '').toString();
    final siteManager =
        (data['siteManagerName'] ?? data['siteManagerId'] ?? 'Unassigned')
            .toString();
    final projectEngineerEmail =
        (data['projectEngineerEmail'] ?? '').toString().trim();
    final projectType = (data['projectType'] ?? '').toString();
    final sourceOfFund = (data['sourceOfFund'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    final contractDocs = (data['contractDocuments'] ?? '').toString();
    final planUrl = (data['planUrl'] ?? '').toString();
    final blueprintCount = (data['blueprintUrls'] is Iterable)
        ? (data['blueprintUrls'] as Iterable).length
        : (planUrl.isEmpty ? 0 : 1);
    final actualCount = (data['referencePhotoUrls'] is Iterable)
        ? (data['referencePhotoUrls'] as Iterable).length
        : 0;
    final planAnalysis =
        (data['planAnalysis'] as Map?)?.cast<String, dynamic>();
    final statusColor = _statusColor(status);
    final formattedStatus =
        status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.deepBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.apartment,
                        color: AppTheme.deepBlue, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Project ID · $projectCode',
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      formattedStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall progress',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppTheme.mediumGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${progress.toStringAsFixed(0)}%',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.deepBlue,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: progress / 100,
                      strokeWidth: 7,
                      backgroundColor:
                          AppTheme.deepBlue.withValues(alpha: 0.08),
                      color: const Color(0xFF2DD4BF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 8,
                  backgroundColor: AppTheme.deepBlue.withValues(alpha: 0.08),
                  color: const Color(0xFF2DD4BF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 640;
            final overview = _InfoSection(
              title: 'Overview',
              icon: Icons.info_outline,
              tiles: [
                _DetailTile(Icons.pin_drop_outlined, 'Location',
                    location.isEmpty ? '—' : location),
                _DetailTile(
                    Icons.person_outline, 'Resident Engineer', siteManager),
                _DetailTile(
                  Icons.alternate_email,
                  'Project Engineer Gmail',
                  projectEngineerEmail.isEmpty ? '—' : projectEngineerEmail,
                ),
                _DetailTile(
                  Icons.architecture_outlined,
                  'Blueprints',
                  '$blueprintCount / 1',
                ),
                _DetailTile(
                  Icons.photo_library_outlined,
                  'Actual project photos',
                  '$actualCount / 1',
                ),
                _DetailTile(Icons.category_outlined, 'Project type',
                    projectType.isEmpty ? '—' : projectType),
                _DetailTile(Icons.account_balance_outlined, 'Source of fund',
                    sourceOfFund.isEmpty ? '—' : sourceOfFund),
              ],
            );
            final timeline = _InfoSection(
              title: 'Timeline & Budget',
              icon: Icons.calendar_month_outlined,
              tiles: [
                _DetailTile(Icons.play_circle_outline, 'Start date',
                    _fmtDate(data['startDate'] as String?)),
                _DetailTile(Icons.flag_outlined, 'End date',
                    _fmtDate(data['endDate'] as String?)),
                _DetailTile(Icons.payments_outlined, 'Approved budget',
                    _fmtBudget(data['approvedBudget'])),
              ],
            );

            if (narrow) {
              return Column(
                children: [overview, const SizedBox(height: 12), timeline],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: overview),
                const SizedBox(width: 12),
                Expanded(child: timeline),
              ],
            );
          },
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TextSection(
            title: 'Description',
            icon: Icons.description_outlined,
            body: description,
          ),
        ],
        if (contractDocs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TextSection(
            title: 'Contract & required papers',
            icon: Icons.folder_open_outlined,
            body: contractDocs,
          ),
        ],
        if (planUrl.isNotEmpty || planAnalysis != null) ...[
          const SizedBox(height: 12),
          _PlanSection(planUrl: planUrl, planAnalysis: planAnalysis),
        ],
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.tiles,
  });

  final String title;
  final IconData icon;
  final List<_DetailTile> tiles;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.deepBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.deepBlue,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tiles.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: t,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTheme.deepBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppTheme.deepBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.mediumGray,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.deepBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.deepBlue,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: const Color(0xFF334155),
                ),
          ),
        ],
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.planUrl,
    this.planAnalysis,
  });

  final String planUrl;
  final Map<String, dynamic>? planAnalysis;

  bool get _isImageUrl {
    final lower = planUrl.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final summary = (planAnalysis?['summary'] ?? '').toString();
    final docType = (planAnalysis?['docType'] ?? '').toString();
    final mlPct = planAnalysis?['progressPercent'];
    final labels =
        (planAnalysis?['labels'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.architecture,
                  size: 18, color: AppTheme.deepBlue),
              const SizedBox(width: 8),
              Text(
                'Project plan & ML analysis',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.deepBlue,
                    ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.deepBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.deepBlue.withValues(alpha: 0.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    docType == 'blueprint'
                        ? Icons.draw_outlined
                        : Icons.photo_camera_outlined,
                    size: 18,
                    color: AppTheme.deepBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (mlPct is num) ...[
                          const SizedBox(height: 4),
                          Text(
                            'ML estimated progress: ${mlPct.toStringAsFixed(0)}%',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppTheme.deepBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (labels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: labels.take(8).map((l) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.mediumGray.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              }).toList(),
            ),
          ],
          if (planUrl.isNotEmpty && _isImageUrl) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                planUrl,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: AppTheme.lightGray,
                  child: const Text('Unable to preview plan image'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
