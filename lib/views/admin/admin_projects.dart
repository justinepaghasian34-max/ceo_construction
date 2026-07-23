import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/firebase_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/archive_service.dart';
import '../../services/govtrack_progress_ml_service.dart';
import 'admin_project_details_screen.dart';
import 'widgets/admin_bottom_nav.dart';
import 'widgets/admin_glass_layout.dart';

Widget _buildPlanUploadSection({
  required BuildContext context,
  required VoidCallback? onPick,
  required bool busy,
  String? fileName,
  String? hint,
}) {
  return GlassCard(
    borderRadius: 16,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.architecture, color: AppTheme.deepBlue, size: 20),
            const SizedBox(width: 8),
            Text(
              'Project Plan & Blueprint',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.deepBlue,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Upload a blueprint (PNG/JPG) or exact site photo. Images run the predefined ML pipeline (Vision + Gemini). PDF/DOC files are stored for reference.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.mediumGray,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPick,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.deepBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload_file),
            label: Text(
              busy ? 'Running ML analysis…' : 'Upload Project Plan',
            ),
          ),
        ),
        if (fileName != null && fileName.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.deepBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.deepBlue.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 18, color: AppTheme.deepBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hint != null && hint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            hint,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.deepBlue,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    ),
  );
}

class AdminProjects extends StatefulWidget {
  const AdminProjects({super.key});

  @override
  State<AdminProjects> createState() => _AdminProjectsState();
}

class _AdminProjectsState extends State<AdminProjects> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final projectsRef = FirebaseService.instance.projectsCollection;

    return AdminGlassScaffold(
      title: 'Construction Projects',
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          onPressed: () => context.push(RouteNames.notifications),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push(RouteNames.profile),
        ),
      ],
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.constructionProjects,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProjectDialog(context),
        backgroundColor: const Color(0xFF2DD4BF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildRecordsTabBar(context),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot>(
          stream: projectsRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Failed to load projects',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.errorRed,
                      ),
                ),
              );
            }

            final docs = (snapshot.data?.docs ?? [])
                .where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final archived = ArchiveService.isArchived(data);
                  return _showArchived ? archived : !archived;
                })
                .toList();

            if (docs.isEmpty) {
              return Center(
                child: Text(
                  _showArchived
                      ? 'No archived projects'
                      : 'No active projects found',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mediumGray,
                      ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] ?? 'Untitled Project').toString();
                final status = (data['status'] ?? 'unknown').toString();
                final progress = (data['progressPercentage'] ?? 0).toDouble();
                final projectId = doc.id;
                final String displayProjectId =
                    (data['projectCode'] ?? projectId).toString();
                const String projectIdLabel = 'Project ID';
                final siteManagerName =
                    (data['siteManagerName'] ?? '').toString();
                final location = (data['location'] ?? '').toString();
                final isArchivedView = _showArchived;
                final archivedOn = isArchivedView
                    ? ArchiveService.formatArchivedAt(data)
                    : null;
                final archivedBy =
                    (data[ArchiveService.fieldArchivedByEmail] ?? '').toString();

                final normalizedStatus = status.toLowerCase();
                final String formattedStatus = isArchivedView
                    ? 'Archived'
                    : (status.isEmpty
                        ? '—'
                        : status[0].toUpperCase() + status.substring(1));
                final Color statusColor = isArchivedView
                    ? AppTheme.mediumGray
                    : normalizedStatus == 'ongoing'
                        ? AppTheme.softGreen
                        : normalizedStatus == 'completed'
                            ? AppTheme.primaryBlue
                            : normalizedStatus == 'pending'
                                ? AppTheme.warningOrange
                                : AppTheme.mediumGray;

                String siteManagerLabel;
                if (siteManagerName.isEmpty) {
                  siteManagerLabel = 'Unassigned';
                } else {
                  siteManagerLabel = siteManagerName;
                }

                return GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.deepBlue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.business,
                              size: 18,
                              color: AppTheme.deepBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$projectIdLabel: $displayProjectId',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppTheme.mediumGray,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (location.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          location,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppTheme.mediumGray,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              formattedStatus,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isArchivedView
                                  ? 'Archived on $archivedOn${archivedBy.isNotEmpty ? ' · $archivedBy' : ''}'
                                  : 'Site manager: $siteManagerLabel',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ),
                          if (!isArchivedView) ...[
                            const SizedBox(width: 12),
                            Text(
                              '${progress.toStringAsFixed(0)}% complete',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.black.withValues(alpha: 0.75),
                                  ),
                            ),
                          ],
                        ],
                      ),
                      if (!isArchivedView) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (progress.clamp(0, 100)) / 100,
                          backgroundColor: Colors.black.withValues(alpha: 0.06),
                          color: const Color(0xFF2DD4BF),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final narrow = constraints.maxWidth < 520;
                          final secondaryActions = [
                            if (!isArchivedView)
                              _ProjectActionButton(
                                label: 'Materials',
                                icon: Icons.inventory_2_outlined,
                                variant: _ProjectActionVariant.neutral,
                                onPressed: () {
                                  final qp = <String, String>{
                                    'projectId': projectId,
                                    if (name.trim().isNotEmpty)
                                      'projectName': name,
                                  };
                                  context.push(
                                    Uri(
                                      path: RouteNames.adminMaterialMonitoring,
                                      queryParameters: qp,
                                    ).toString(),
                                  );
                                },
                              ),
                            _ProjectActionButton(
                              label: 'View',
                              icon: Icons.visibility_outlined,
                              variant: _ProjectActionVariant.neutral,
                              onPressed: () {
                                _openProjectDetails(
                                  context,
                                  projectId,
                                  projectIdLabel,
                                  name,
                                  status,
                                  progress,
                                  location,
                                  siteManagerLabel,
                                  data,
                                );
                              },
                            ),
                          ];
                          final crudActions = isArchivedView
                              ? [
                                  _ProjectActionButton(
                                    label: 'Restore',
                                    icon: Icons.unarchive_outlined,
                                    variant: _ProjectActionVariant.restore,
                                    onPressed: () {
                                      _confirmRestoreProject(
                                        context,
                                        projectId: projectId,
                                        projectName: name,
                                      );
                                    },
                                  ),
                                ]
                              : [
                                  _ProjectActionButton(
                                    label: 'Edit',
                                    icon: Icons.edit_outlined,
                                    variant: _ProjectActionVariant.edit,
                                    onPressed: () {
                                      _showEditProjectDialog(
                                        context,
                                        projectId,
                                        data,
                                      );
                                    },
                                  ),
                                  _ProjectActionButton(
                                    label: 'Archive',
                                    icon: Icons.archive_outlined,
                                    variant: _ProjectActionVariant.delete,
                                    onPressed: () {
                                      _confirmAndArchiveProject(
                                        context,
                                        projectId: projectId,
                                        projectName: name,
                                        siteManagerId:
                                            (data['siteManagerId'] ?? '')
                                                .toString(),
                                        previousStatus: status,
                                      );
                                    },
                                  ),
                                ];

                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: [...secondaryActions, ...crudActions],
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              ...secondaryActions.map(
                                (w) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: w,
                                ),
                              ),
                              const Spacer(),
                              ...crudActions.map(
                                (w) => Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: w,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsTabBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.deepBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.deepBlue.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RecordsTabChip(
              label: 'Active',
              icon: Icons.folder_open_outlined,
              selected: !_showArchived,
              onTap: () => setState(() => _showArchived = false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _RecordsTabChip(
              label: 'Archived',
              icon: Icons.inventory_2_outlined,
              selected: _showArchived,
              onTap: () => setState(() => _showArchived = true),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndArchiveProject(
    BuildContext context, {
    required String projectId,
    required String projectName,
    required String siteManagerId,
    required String previousStatus,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.archive_outlined, color: AppTheme.errorRed),
              SizedBox(width: 10),
              Text('Archive project?'),
            ],
          ),
          content: Text(
            'Archive "$projectName"? It will be removed from active lists but '
            'kept in the system for audit and review.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.errorRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Archive'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ArchiveService.instance.archiveProject(
        projectId: projectId,
        projectName: projectName,
        siteManagerId: siteManagerId,
        previousStatus: previousStatus,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archived "$projectName" — data retained for audit'),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to archive project: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  Future<void> _confirmRestoreProject(
    BuildContext context, {
    required String projectId,
    required String projectName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Restore project?'),
          content: Text(
            'Restore "$projectName" to the active projects list?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.deepBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ArchiveService.instance.restoreProject(
        projectId: projectId,
        projectName: projectName,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restored "$projectName"'),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore project: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  void _openProjectDetails(
    BuildContext context,
    String projectId,
    String projectIdLabel,
    String name,
    String status,
    double progress,
    String location,
    String siteManagerLabel,
    Map<String, dynamic> data,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminProjectDetailsScreen(projectId: projectId),
      ),
    );
  }

  static void _showAddProjectDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    final contractDocsController = TextEditingController();
    final budgetController = TextEditingController();

    String? projectType;
    String? sourceOfFund;
    DateTime? startDate;
    DateTime? endDate;
    String? selectedSiteManagerValue;
    String? siteManagerId;
    String? siteManagerName;
    final inspectorNameController = TextEditingController();
    String? planFileName;
    dynamic planFileBytes;
    String? planMlHint;
    bool isAnalyzingPlan = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> pickPlanFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  ...AppConstants.allowedImageTypes,
                  ...AppConstants.allowedDocumentTypes,
                ],
                withData: true,
              );

              if (result == null || result.files.isEmpty) {
                return;
              }

              final file = result.files.single;
              final name = file.name.toLowerCase();
              final isImage = name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.webp');
              setState(() {
                planFileName = file.name;
                planFileBytes = file.bytes;
                planMlHint = isImage
                    ? 'Blueprint or site photo — ML analysis will run on create.'
                    : 'PDF/DOC stored for reference. Use JPG/PNG for ML analysis.';
              });
            }

            Future<void> selectDate({required bool isStart}) async {
              final initial = isStart
                  ? (startDate ?? DateTime.now())
                  : (endDate ?? startDate ?? DateTime.now());
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  if (isStart) {
                    startDate = picked;
                    if (endDate != null && endDate!.isBefore(startDate!)) {
                      endDate = startDate;
                    }
                  } else {
                    endDate = picked;
                  }
                });
              }
            }

            InputDecoration fieldDecoration(String label, {String? hint}) {
              return InputDecoration(
                labelText: label,
                hintText: hint,
                filled: true,
                fillColor: AppTheme.lightGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              );
            }

            TextStyle? headingStyle() {
              return Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                color: AppTheme.deepBlue,
                fontWeight: FontWeight.w600,
              );
            }

            String? inferContentType(String? fileName) {
              if (fileName == null || fileName.isEmpty) return null;
              final parts = fileName.split('.');
              if (parts.length < 2) return null;
              final ext = parts.last.toLowerCase();
              switch (ext) {
                case 'jpg':
                case 'jpeg':
                  return 'image/jpeg';
                case 'png':
                  return 'image/png';
                case 'webp':
                  return 'image/webp';
                case 'pdf':
                  return 'application/pdf';
                case 'doc':
                  return 'application/msword';
                case 'docx':
                  return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
                default:
                  return null;
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              title: Row(
                children: [
                  Icon(Icons.business, color: AppTheme.deepBlue),
                  const SizedBox(width: 12),
                  Text('Create Project', style: headingStyle()),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: fieldDecoration('Project Name'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a project name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: locationController,
                        decoration: fieldDecoration('Project Location'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: projectType,
                        decoration: fieldDecoration('Project Type'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'building',
                            child: Text('Building'),
                          ),
                          DropdownMenuItem(value: 'road', child: Text('Road')),
                          DropdownMenuItem(
                            value: 'bridge',
                            child: Text('Bridge'),
                          ),
                          DropdownMenuItem(
                            value: 'flood_control',
                            child: Text('Flood Control'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            projectType = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a project type';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      GlassCard(
                        borderRadius: 16,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: false,
                              onChanged: null,
                              title: const Text('Use Material Template'),
                              subtitle: const Text('Auto-populate assigned materials (budget list) from a template.'),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descriptionController,
                        decoration: fieldDecoration('Project Description'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: contractDocsController,
                        decoration: fieldDecoration(
                          'Contract & required papers (optional)',
                          hint: 'e.g. Contract agreement, permits, clearances',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => selectDate(isStart: true),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: fieldDecoration('Start Date'),
                                  controller: TextEditingController(
                                    text: startDate == null
                                        ? ''
                                        : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                                  ),
                                  validator: (value) {
                                    if (startDate == null) {
                                      return 'Select start date';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => selectDate(isStart: false),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: fieldDecoration(
                                    'End Date (optional)',
                                  ),
                                  controller: TextEditingController(
                                    text: endDate == null
                                        ? ''
                                        : '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                                  ),
                                  validator: (value) {
                                    if (endDate != null &&
                                        startDate != null &&
                                        endDate!.isBefore(startDate!)) {
                                      return 'End date must be after start date';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: budgetController,
                        keyboardType: TextInputType.number,
                        decoration: fieldDecoration(
                          'Approved Budget',
                          hint: 'e.g. 10000000',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter approved budget';
                          }
                          final parsed = double.tryParse(
                            value
                                .replaceAll(',', '')
                                .replaceAll('₱', '')
                                .trim(),
                          );
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: sourceOfFund,
                        decoration: fieldDecoration('Source of Fund'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'national',
                            child: Text('National Government'),
                          ),
                          DropdownMenuItem(
                            value: 'local',
                            child: Text('Local Government'),
                          ),
                          DropdownMenuItem(value: 'loan', child: Text('Loan')),
                          DropdownMenuItem(
                            value: 'grant',
                            child: Text('Grant'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            sourceOfFund = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select source of fund';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseService.instance.usersCollection
                            .where(
                              'role',
                              isEqualTo: AppConstants.roleSiteManager,
                            )
                            .where('isActive', isEqualTo: true)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const LinearProgressIndicator();
                          }

                          if (snapshot.hasError) {
                            return Text(
                              'Failed to load site managers',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.errorRed),
                            );
                          }

                          final users = snapshot.data?.docs ?? [];
                          if (users.isEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No site manager accounts found.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: inspectorNameController,
                                  decoration: fieldDecoration(
                                    'Assigned Inspector (optional)',
                                    hint: 'Enter inspector name',
                                  ),
                                ),
                              ],
                            );
                          }

                          List<DropdownMenuItem<String>> buildItems() {
                            return users.map((userDoc) {
                              final data =
                                  userDoc.data() as Map<String, dynamic>;
                              final userId = userDoc.id;
                              final firstName = (data['firstName'] ?? '')
                                  .toString();
                              final lastName = (data['lastName'] ?? '')
                                  .toString();
                              final email = (data['email'] ?? '').toString();
                              final fullName = ('$firstName $lastName').trim();
                              final displayName = fullName.isNotEmpty
                                  ? fullName
                                  : email;
                              final value = '$userId|$displayName';
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(displayName),
                              );
                            }).toList();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: selectedSiteManagerValue,
                                decoration: fieldDecoration(
                                  'Assigned Site Manager',
                                ),
                                isExpanded: true,
                                items: buildItems(),
                                onChanged: (value) {
                                  setState(() {
                                    selectedSiteManagerValue = value;
                                    if (value == null) {
                                      siteManagerId = null;
                                      siteManagerName = null;
                                    } else {
                                      final parts = value.split('|');
                                      siteManagerId = parts.first;
                                      siteManagerName = parts.length > 1
                                          ? parts[1]
                                          : null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: inspectorNameController,
                                decoration: fieldDecoration(
                                  'Assigned Inspector (optional)',
                                  hint: 'Enter inspector name',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildPlanUploadSection(
                        context: dialogContext,
                        onPick: isSaving || isAnalyzingPlan ? null : pickPlanFile,
                        busy: isAnalyzingPlan,
                        fileName: planFileName,
                        hint: planMlHint,
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  Navigator.pop(dialogContext);
                                },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }

                                  setState(() {
                                    isSaving = true;
                                  });

                                  try {
                                    final now = DateTime.now();
                                    final nowIso = now.toIso8601String();
                                    final budgetValue = double.parse(
                                      budgetController.text
                                          .replaceAll(',', '')
                                          .replaceAll('₱', '')
                                          .trim(),
                                    );

                                    final projectsRef = FirebaseService
                                        .instance
                                        .projectsCollection;
                                    final newProjectRef = projectsRef.doc();
                                    final newProjectId = newProjectRef.id;
                                    final projectCode = await FirebaseService
                                        .instance
                                        .generateProjectCode();

                                    final Map<String, dynamic> baseData = {
                                      'name': nameController.text.trim(),
                                      'location':
                                          locationController.text.trim().isEmpty
                                          ? null
                                          : locationController.text.trim(),
                                      'projectType': projectType,
                                      'description':
                                          descriptionController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : descriptionController.text.trim(),
                                      'contractDocuments':
                                          contractDocsController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : contractDocsController.text.trim(),
                                      'startDate': startDate?.toIso8601String(),
                                      'endDate': endDate?.toIso8601String(),
                                      'approvedBudget': budgetValue,
                                      'sourceOfFund': sourceOfFund,
                                      'siteManagerId': siteManagerId,
                                      'siteManagerName': siteManagerName,
                                      'projectCode': projectCode,
                                      'inspectorId': null,
                                      'inspectorName':
                                          inspectorNameController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : inspectorNameController.text.trim(),
                                      'planUrl': null,
                                      'status': 'ongoing',
                                      'progressPercentage': 0,
                                      'createdAt': nowIso,
                                      'updatedAt': nowIso,
                                    };

                                    await newProjectRef
                                        .set(baseData)
                                        .timeout(const Duration(seconds: 20));

                                    // If a site manager is assigned at creation time, sync assignedProjects
                                    if (siteManagerId != null &&
                                        siteManagerId!.isNotEmpty) {
                                      final usersCollection = FirebaseService
                                          .instance
                                          .usersCollection;
                                      final siteManagerRef = usersCollection
                                          .doc(siteManagerId);
                                      final siteManagerSnap =
                                          await siteManagerRef.get().timeout(
                                            const Duration(seconds: 20),
                                          );
                                      if (siteManagerSnap.exists) {
                                        final userData =
                                            siteManagerSnap.data()
                                                as Map<String, dynamic>;
                                        final List<dynamic> assigned =
                                            List<dynamic>.from(
                                              userData['assignedProjects'] ??
                                                  [],
                                            );
                                        if (!assigned.contains(newProjectId)) {
                                          assigned.add(newProjectId);
                                          await siteManagerRef
                                              .update({
                                                'assignedProjects': assigned,
                                                'updatedAt': now,
                                              })
                                              .timeout(
                                                const Duration(seconds: 20),
                                              );
                                        }
                                      }
                                    }

                                    // Log project creation to audit trail (best-effort)
                                    await AuditLogService.instance.logAction(
                                      action: 'project_created',
                                      projectId: newProjectId,
                                      details: {
                                        'name': baseData['name'],
                                        'location': baseData['location'],
                                        'projectType': projectType,
                                        'approvedBudget': budgetValue,
                                        'sourceOfFund': sourceOfFund,
                                        'siteManagerId': siteManagerId,
                                        'siteManagerName': siteManagerName,
                                      },
                                    );

                                    if (planFileBytes != null) {
                                      setState(() => isAnalyzingPlan = true);
                                      try {
                                        final bytes = planFileBytes is Uint8List
                                            ? planFileBytes as Uint8List
                                            : Uint8List.fromList(
                                                planFileBytes as List<int>,
                                              );
                                        final result = await GovtrackProgressMlService()
                                            .analyzeProjectPlan(
                                              projectId: newProjectId,
                                              projectName:
                                                  nameController.text.trim(),
                                              fileBytes: bytes,
                                              fileName: planFileName ??
                                                  'project_plan.jpg',
                                            );
                                        final planUpdate = <String, dynamic>{
                                          'planUrl': result.planUrl,
                                          'planAnalysis':
                                              result.toFirestoreMap(),
                                          'updatedAt': nowIso,
                                        };
                                        if (result.progressPercent != null &&
                                            !result.mlSkipped) {
                                          planUpdate['progressPercentage'] =
                                              result.progressPercent;
                                        }
                                        await newProjectRef.update(planUpdate);
                                      } catch (_) {
                                        // Plan upload is best-effort; project already created.
                                      } finally {
                                        if (context.mounted) {
                                          setState(() => isAnalyzingPlan = false);
                                        }
                                      }
                                    }

                                    if (context.mounted) {
                                      Navigator.pop(dialogContext);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Project created'),
                                          backgroundColor: AppTheme.softGreen,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to create project: $e',
                                          ),
                                          backgroundColor: AppTheme.errorRed,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.softGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Create Project'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditProjectDialog(
    BuildContext context,
    String projectId,
    Map<String, dynamic> data,
  ) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: (data['name'] ?? '').toString(),
    );
    final locationController = TextEditingController(
      text: (data['location'] ?? '').toString(),
    );
    final descriptionController = TextEditingController(
      text: (data['description'] ?? '').toString(),
    );
    final contractDocsController = TextEditingController(
      text: (data['contractDocuments'] ?? '').toString(),
    );
    final budgetController = TextEditingController();

    String? projectType = (data['projectType'] ?? '').toString();
    if (projectType.isEmpty) projectType = null;

    String? sourceOfFund = (data['sourceOfFund'] ?? '').toString();
    if (sourceOfFund.isEmpty) sourceOfFund = null;

    DateTime? startDate;
    DateTime? endDate;

    final startDateStr = data['startDate'] as String?;
    if (startDateStr != null && startDateStr.isNotEmpty) {
      try {
        startDate = DateTime.parse(startDateStr);
      } catch (_) {}
    }

    final endDateStr = data['endDate'] as String?;
    if (endDateStr != null && endDateStr.isNotEmpty) {
      try {
        endDate = DateTime.parse(endDateStr);
      } catch (_) {}
    }

    final rawBudget = data['approvedBudget'] ?? data['contractAmount'];
    if (rawBudget is num) {
      budgetController.text = rawBudget.toDouble().toString();
    } else if (rawBudget is String) {
      final parsed = double.tryParse(rawBudget);
      if (parsed != null) {
        budgetController.text = parsed.toString();
      }
    }

    String? siteManagerId = (data['siteManagerId'] ?? '') as String?;
    String? siteManagerName = (data['siteManagerName'] ?? '') as String?;
    String? inspectorName = (data['inspectorName'] ?? '') as String?;

    if (siteManagerId != null && siteManagerId.isEmpty) siteManagerId = null;
    if (siteManagerName != null && siteManagerName.isEmpty) {
      siteManagerName = null;
    }
    if (inspectorName != null && inspectorName.isEmpty) {
      inspectorName = null;
    }

    String? selectedSiteManagerValue =
        siteManagerId != null && siteManagerName != null
        ? '$siteManagerId|$siteManagerName'
        : null;
    final inspectorNameController = TextEditingController(
      text: inspectorName ?? '',
    );

    String? existingPlanUrl = (data['planUrl'] ?? '') as String?;
    String? planFileName;
    if (existingPlanUrl != null && existingPlanUrl.isNotEmpty) {
      planFileName =
          Uri.tryParse(existingPlanUrl)?.pathSegments.last ?? 'Existing plan';
    }
    dynamic planFileBytes;
    String? planMlHint;
    bool isAnalyzingPlan = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> pickPlanFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  ...AppConstants.allowedImageTypes,
                  ...AppConstants.allowedDocumentTypes,
                ],
                withData: true,
              );

              if (result == null || result.files.isEmpty) {
                return;
              }

              final file = result.files.single;
              final name = file.name.toLowerCase();
              final isImage = name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.webp');
              setState(() {
                planFileName = file.name;
                planFileBytes = file.bytes;
                planMlHint = isImage
                    ? 'Blueprint or site photo — ML analysis will run on save.'
                    : 'PDF/DOC stored for reference. Use JPG/PNG for ML analysis.';
              });
            }

            Future<void> selectDate({required bool isStart}) async {
              final initial = isStart
                  ? (startDate ?? DateTime.now())
                  : (endDate ?? startDate ?? DateTime.now());
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  if (isStart) {
                    startDate = picked;
                    if (endDate != null && endDate!.isBefore(startDate!)) {
                      endDate = startDate;
                    }
                  } else {
                    endDate = picked;
                  }
                });
              }
            }

            InputDecoration fieldDecoration(String label, {String? hint}) {
              return InputDecoration(
                labelText: label,
                hintText: hint,
                filled: true,
                fillColor: AppTheme.lightGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              );
            }

            TextStyle? headingStyle() {
              return Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                color: AppTheme.deepBlue,
                fontWeight: FontWeight.w600,
              );
            }

            String? inferContentType(String? fileName) {
              if (fileName == null || fileName.isEmpty) return null;
              final parts = fileName.split('.');
              if (parts.length < 2) return null;
              final ext = parts.last.toLowerCase();
              switch (ext) {
                case 'jpg':
                case 'jpeg':
                  return 'image/jpeg';
                case 'png':
                  return 'image/png';
                case 'webp':
                  return 'image/webp';
                case 'pdf':
                  return 'application/pdf';
                case 'doc':
                  return 'application/msword';
                case 'docx':
                  return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
                default:
                  return null;
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              title: Row(
                children: [
                  Icon(Icons.business, color: AppTheme.deepBlue),
                  const SizedBox(width: 12),
                  Text('Edit Project', style: headingStyle()),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController,
                        decoration: fieldDecoration('Project Name'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a project name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: locationController,
                        decoration: fieldDecoration('Project Location'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: projectType,
                        decoration: fieldDecoration('Project Type'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'building',
                            child: Text('Building'),
                          ),
                          DropdownMenuItem(value: 'road', child: Text('Road')),
                          DropdownMenuItem(
                            value: 'bridge',
                            child: Text('Bridge'),
                          ),
                          DropdownMenuItem(
                            value: 'flood_control',
                            child: Text('Flood Control'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            projectType = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a project type';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descriptionController,
                        decoration: fieldDecoration('Project Description'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: contractDocsController,
                        decoration: fieldDecoration(
                          'Contract & required papers (optional)',
                          hint: 'e.g. Contract agreement, permits, clearances',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => selectDate(isStart: true),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: fieldDecoration('Start Date'),
                                  controller: TextEditingController(
                                    text: startDate == null
                                        ? ''
                                        : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}',
                                  ),
                                  validator: (value) {
                                    if (startDate == null) {
                                      return 'Select start date';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => selectDate(isStart: false),
                              child: AbsorbPointer(
                                child: TextFormField(
                                  decoration: fieldDecoration(
                                    'End Date (optional)',
                                  ),
                                  controller: TextEditingController(
                                    text: endDate == null
                                        ? ''
                                        : '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}',
                                  ),
                                  validator: (value) {
                                    if (endDate != null &&
                                        startDate != null &&
                                        endDate!.isBefore(startDate!)) {
                                      return 'End date must be after start date';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: budgetController,
                        keyboardType: TextInputType.number,
                        decoration: fieldDecoration(
                          'Approved Budget',
                          hint: 'e.g. 10000000',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter approved budget';
                          }
                          final parsed = double.tryParse(
                            value
                                .replaceAll(',', '')
                                .replaceAll('₱', '')
                                .trim(),
                          );
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: sourceOfFund,
                        decoration: fieldDecoration('Source of Fund'),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'national',
                            child: Text('National Government'),
                          ),
                          DropdownMenuItem(
                            value: 'local',
                            child: Text('Local Government'),
                          ),
                          DropdownMenuItem(value: 'loan', child: Text('Loan')),
                          DropdownMenuItem(
                            value: 'grant',
                            child: Text('Grant'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            sourceOfFund = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select source of fund';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<QuerySnapshot>(
                        future: FirebaseService.instance.usersCollection
                            .where(
                              'role',
                              isEqualTo: AppConstants.roleSiteManager,
                            )
                            .where('isActive', isEqualTo: true)
                            .get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const LinearProgressIndicator();
                          }

                          if (snapshot.hasError) {
                            return Text(
                              'Failed to load site managers',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.errorRed),
                            );
                          }

                          final users = snapshot.data?.docs ?? [];
                          if (users.isEmpty) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No site manager accounts found.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.mediumGray),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: inspectorNameController,
                                  decoration: fieldDecoration(
                                    'Assigned Inspector (optional)',
                                    hint: 'Enter inspector name',
                                  ),
                                ),
                              ],
                            );
                          }

                          List<DropdownMenuItem<String>> buildItems() {
                            return users.map((userDoc) {
                              final udata =
                                  userDoc.data() as Map<String, dynamic>;
                              final userId = userDoc.id;
                              final firstName = (udata['firstName'] ?? '')
                                  .toString();
                              final lastName = (udata['lastName'] ?? '')
                                  .toString();
                              final email = (udata['email'] ?? '').toString();
                              final fullName = ('$firstName $lastName').trim();
                              final displayName = fullName.isNotEmpty
                                  ? fullName
                                  : email;
                              final value = '$userId|$displayName';
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(displayName),
                              );
                            }).toList();
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: selectedSiteManagerValue,
                                decoration: fieldDecoration(
                                  'Assigned Site Manager',
                                ),
                                isExpanded: true,
                                items: buildItems(),
                                onChanged: (value) {
                                  setState(() {
                                    selectedSiteManagerValue = value;
                                    if (value == null) {
                                      siteManagerId = null;
                                      siteManagerName = null;
                                    } else {
                                      final parts = value.split('|');
                                      siteManagerId = parts.first;
                                      siteManagerName = parts.length > 1
                                          ? parts[1]
                                          : null;
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: inspectorNameController,
                                decoration: fieldDecoration(
                                  'Assigned Inspector (optional)',
                                  hint: 'Enter inspector name',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildPlanUploadSection(
                        context: dialogContext,
                        onPick: isSaving || isAnalyzingPlan ? null : pickPlanFile,
                        busy: isAnalyzingPlan,
                        fileName: planFileName,
                        hint: planMlHint,
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isSaving
                              ? null
                              : () {
                                  Navigator.pop(dialogContext);
                                },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }

                                  setState(() {
                                    isSaving = true;
                                  });

                                  try {
                                    final now = DateTime.now()
                                        .toIso8601String();
                                    final budgetValue = double.parse(
                                      budgetController.text
                                          .replaceAll(',', '')
                                          .replaceAll('\\u0000', '')
                                          .trim(),
                                    );

                                    String? planUrl = existingPlanUrl;
                                    Map<String, dynamic>? planAnalysis;
                                    double? mlProgress;

                                    if (planFileBytes != null) {
                                      setState(() => isAnalyzingPlan = true);
                                      try {
                                        final bytes = planFileBytes is Uint8List
                                            ? planFileBytes as Uint8List
                                            : Uint8List.fromList(
                                                planFileBytes as List<int>,
                                              );
                                        final result =
                                            await GovtrackProgressMlService()
                                                .analyzeProjectPlan(
                                          projectId: projectId,
                                          projectName:
                                              nameController.text.trim(),
                                          fileBytes: bytes,
                                          fileName: planFileName ??
                                              'project_plan.jpg',
                                        );
                                        planUrl = result.planUrl;
                                        planAnalysis = result.toFirestoreMap();
                                        if (result.progressPercent != null &&
                                            !result.mlSkipped) {
                                          mlProgress = result.progressPercent;
                                        }
                                      } finally {
                                        if (context.mounted) {
                                          setState(() => isAnalyzingPlan = false);
                                        }
                                      }
                                    }

                                    await FirebaseService
                                        .instance
                                        .projectsCollection
                                        .doc(projectId)
                                        .update({
                                          'name': nameController.text.trim(),
                                          'location':
                                              locationController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : locationController.text.trim(),
                                          'projectType': projectType,
                                          'description':
                                              descriptionController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : descriptionController.text
                                                    .trim(),
                                          'contractDocuments':
                                              contractDocsController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : contractDocsController.text
                                                    .trim(),
                                          'startDate': startDate
                                              ?.toIso8601String(),
                                          'endDate': endDate?.toIso8601String(),
                                          'approvedBudget': budgetValue,
                                          'sourceOfFund': sourceOfFund,
                                          'siteManagerId': siteManagerId,
                                          'siteManagerName': siteManagerName,
                                          'inspectorId': null,
                                          'inspectorName':
                                              inspectorNameController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : inspectorNameController.text
                                                    .trim(),
                                          'planUrl': planUrl,
                                          if (planAnalysis != null)
                                            'planAnalysis': planAnalysis,
                                          if (mlProgress != null)
                                            'progressPercentage': mlProgress,
                                          'updatedAt': now,
                                        });

                                    // Log project update to audit trail (best-effort)
                                    await AuditLogService.instance.logAction(
                                      action: 'project_updated',
                                      projectId: projectId,
                                      details: {
                                        'name': nameController.text.trim(),
                                        'location':
                                            locationController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : locationController.text.trim(),
                                        'projectType': projectType,
                                        'approvedBudget': budgetValue,
                                        'sourceOfFund': sourceOfFund,
                                        'siteManagerId': siteManagerId,
                                        'siteManagerName': siteManagerName,
                                        'inspectorName':
                                            inspectorNameController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : inspectorNameController.text
                                                  .trim(),
                                      },
                                    );

                                    if (!context.mounted) return;

                                    Navigator.pop(dialogContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Project updated'),
                                        backgroundColor: AppTheme.softGreen,
                                      ),
                                    );
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to update project: $e',
                                          ),
                                          backgroundColor: AppTheme.errorRed,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setState(() {
                                        isSaving = false;
                                      });
                                    }
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.softGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _ProjectActionVariant { neutral, edit, delete, restore }

class _ProjectActionButton extends StatefulWidget {
  const _ProjectActionButton({
    required this.label,
    required this.icon,
    required this.variant,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final _ProjectActionVariant variant;
  final VoidCallback onPressed;

  @override
  State<_ProjectActionButton> createState() => _ProjectActionButtonState();
}

class _ProjectActionButtonState extends State<_ProjectActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.variant == _ProjectActionVariant.edit;
    final isDelete = widget.variant == _ProjectActionVariant.delete;
    final isRestore = widget.variant == _ProjectActionVariant.restore;

    final Color fg;
    final Color bg;
    final Color border;
    if (isEdit) {
      fg = Colors.white;
      bg = AppTheme.deepBlue;
      border = AppTheme.deepBlue;
    } else if (isDelete) {
      fg = AppTheme.errorRed;
      bg = AppTheme.errorRed.withValues(alpha: 0.08);
      border = AppTheme.errorRed.withValues(alpha: 0.45);
    } else if (isRestore) {
      fg = AppTheme.softGreen;
      bg = AppTheme.softGreen.withValues(alpha: 0.1);
      border = AppTheme.softGreen.withValues(alpha: 0.45);
    } else {
      fg = AppTheme.deepBlue;
      bg = AppTheme.deepBlue.withValues(alpha: 0.06);
      border = AppTheme.deepBlue.withValues(alpha: 0.18);
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isEdit && _pressed
                ? AppTheme.deepBlueDark
                : (isDelete && _pressed
                    ? AppTheme.errorRed.withValues(alpha: 0.16)
                    : (isRestore && _pressed
                        ? AppTheme.softGreen.withValues(alpha: 0.18)
                        : bg)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
            boxShadow: _pressed
                ? []
                : [
                    BoxShadow(
                      color: (isDelete
                              ? AppTheme.errorRed
                              : isRestore
                                  ? AppTheme.softGreen
                                  : AppTheme.deepBlue)
                          .withValues(alpha: isEdit ? 0.22 : 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordsTabChip extends StatelessWidget {
  const _RecordsTabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.deepBlue : AppTheme.mediumGray,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? AppTheme.deepBlue : AppTheme.mediumGray,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
