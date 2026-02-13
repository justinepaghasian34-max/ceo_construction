import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/firebase_service.dart';
import '../../services/audit_log_service.dart';
import '../../widgets/common/app_card.dart';
import 'widgets/admin_bottom_nav.dart';

class AdminProjects extends StatelessWidget {
  const AdminProjects({super.key});

  @override
  Widget build(BuildContext context) {
    final projectsRef = FirebaseService.instance.projectsCollection;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'Construction Projects',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: projectsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Failed to load projects',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.errorRed),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No projects found',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.mediumGray),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = (data['name'] ?? 'Untitled Project').toString();
              final status = (data['status'] ?? 'unknown').toString();
              final progress = (data['progressPercentage'] ?? 0).toDouble();
              final projectId = doc.id;
              final String displayProjectId = (data['projectCode'] ?? projectId)
                  .toString();
              const String projectIdLabel = 'Project ID';
              final siteManagerName = (data['siteManagerName'] ?? '')
                  .toString();
              final location = (data['location'] ?? '').toString();

              final normalizedStatus = status.toLowerCase();
              Color statusColor;
              if (normalizedStatus == 'ongoing') {
                statusColor = AppTheme.softGreen;
              } else if (normalizedStatus == 'completed') {
                statusColor = AppTheme.primaryBlue;
              } else if (normalizedStatus == 'pending') {
                statusColor = AppTheme.warningOrange;
              } else {
                statusColor = AppTheme.mediumGray;
              }

              String formattedStatus;
              if (status.isEmpty) {
                formattedStatus = '—';
              } else {
                formattedStatus = status[0].toUpperCase() + status.substring(1);
              }

              String siteManagerLabel;
              if (siteManagerName.isEmpty) {
                siteManagerLabel = 'Unassigned';
              } else {
                siteManagerLabel = siteManagerName;
              }

              return AppCard(
                onTap: () {
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
                            color: AppTheme.deepBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
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
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
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
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            formattedStatus,
                            style: Theme.of(context).textTheme.bodySmall
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
                            'Site manager: $siteManagerLabel',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.mediumGray),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${progress.toStringAsFixed(0)}% complete',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (progress.clamp(0, 100)) / 100,
                      backgroundColor: AppTheme.lightGray,
                      color: AppTheme.softGreen,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            _showEditProjectDialog(context, projectId, data);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
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
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View details'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const AdminBottomNavBar(
        current: AdminNavItem.constructionProjects,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddProjectDialog(context),
        backgroundColor: AppTheme.softGreen,
        child: const Icon(Icons.add),
      ),
    );
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
      MaterialPageRoute(
        builder: (detailContext) {
          final projectType = (data['projectType'] ?? '').toString();
          final description = (data['description'] ?? '').toString();
          final contractDocs = (data['contractDocuments'] ?? '').toString();
          final sourceOfFund = (data['sourceOfFund'] ?? '').toString();
          final approvedBudgetRaw = data['approvedBudget'];
          String approvedBudgetText = '';
          if (approvedBudgetRaw is num) {
            approvedBudgetText = approvedBudgetRaw.toStringAsFixed(2);
          } else if (approvedBudgetRaw is String &&
              approvedBudgetRaw.isNotEmpty) {
            approvedBudgetText = approvedBudgetRaw;
          }

          String? startDateText;
          final startDateStr = data['startDate'] as String?;
          if (startDateStr != null && startDateStr.isNotEmpty) {
            try {
              final d = DateTime.parse(startDateStr);
              startDateText =
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          String? endDateText;
          final endDateStr = data['endDate'] as String?;
          if (endDateStr != null && endDateStr.isNotEmpty) {
            try {
              final d = DateTime.parse(endDateStr);
              endDateText =
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            } catch (_) {}
          }

          final statusText = '$status (${progress.toStringAsFixed(0)}%)';
          final displayProjectId = (data['projectCode'] ?? projectId)
              .toString();

          return Scaffold(
            appBar: AppBar(title: const Text('Project details')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(detailContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    detailContext,
                    projectIdLabel,
                    displayProjectId,
                  ),
                  _buildDetailRow(detailContext, 'Status', statusText),
                  if (location.isNotEmpty)
                    _buildDetailRow(detailContext, 'Location', location),
                  _buildDetailRow(
                    detailContext,
                    'Site manager',
                    siteManagerLabel,
                  ),
                  if (projectType.isNotEmpty)
                    _buildDetailRow(detailContext, 'Project type', projectType),
                  if (sourceOfFund.isNotEmpty)
                    _buildDetailRow(
                      detailContext,
                      'Source of fund',
                      sourceOfFund,
                    ),
                  if (approvedBudgetText.isNotEmpty)
                    _buildDetailRow(
                      detailContext,
                      'Approved budget',
                      '₱$approvedBudgetText',
                    ),
                  if (startDateText != null)
                    _buildDetailRow(detailContext, 'Start date', startDateText),
                  if (endDateText != null)
                    _buildDetailRow(detailContext, 'End date', endDateText),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Description',
                      style: Theme.of(detailContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(detailContext).textTheme.bodyMedium,
                    ),
                  ],
                  if (contractDocs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Contract & required papers',
                      style: Theme.of(detailContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      contractDocs,
                      style: Theme.of(detailContext).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddProjectDialog(BuildContext context) {
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
              setState(() {
                planFileName = file.name;
                planFileBytes = file.bytes;
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
              backgroundColor: AppTheme.lightGray,
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
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isSaving ? null : pickPlanFile,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.deepBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload Project Plan'),
                            ),
                          ),
                        ],
                      ),
                      if (planFileName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          planFileName!,
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ],
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
                                      () async {
                                        try {
                                          final fileName =
                                              planFileName ??
                                              'project_plan_${DateTime.now().millisecondsSinceEpoch}';
                                          final path =
                                              'projects/$newProjectId/project_plans/$fileName';
                                          final contentType = inferContentType(
                                            fileName,
                                          );
                                          final uploadedUrl =
                                              await FirebaseService.instance
                                                  .uploadFile(
                                                    path,
                                                    planFileBytes,
                                                    contentType: contentType,
                                                  )
                                                  .timeout(
                                                    const Duration(seconds: 30),
                                                  );

                                          await newProjectRef
                                              .update({
                                                'planUrl': uploadedUrl,
                                                'updatedAt': DateTime.now()
                                                    .toIso8601String(),
                                              })
                                              .timeout(
                                                const Duration(seconds: 20),
                                              );
                                        } catch (_) {
                                          // Ignore upload failures for this background task.
                                        }
                                      }();
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
                allowedExtensions: [...AppConstants.allowedDocumentTypes],
                withData: true,
              );

              if (result == null || result.files.isEmpty) {
                return;
              }

              final file = result.files.single;
              setState(() {
                planFileName = file.name;
                planFileBytes = file.bytes;
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
              backgroundColor: AppTheme.lightGray,
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
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isSaving ? null : pickPlanFile,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.deepBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload Project Plan'),
                            ),
                          ),
                        ],
                      ),
                      if (planFileName != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          planFileName!,
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ],
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
                                          .replaceAll(' ', '')
                                          .trim(),
                                    );

                                    String? planUrl = existingPlanUrl;
                                    if (planFileBytes != null) {
                                      final fileName =
                                          planFileName ??
                                          'project_plan_${DateTime.now().millisecondsSinceEpoch}';
                                      final path =
                                          'projects/$projectId/project_plans/$fileName';
                                      final contentType = inferContentType(
                                        fileName,
                                      );
                                      planUrl = await FirebaseService.instance
                                          .uploadFile(
                                            path,
                                            planFileBytes,
                                            contentType: contentType,
                                          );
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

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.mediumGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
