import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/geo_tag_service.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/audit_log_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common/app_button.dart';
import 'widgets/site_manager_card.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _materialNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _purposeController = TextEditingController();

  bool _isSubmitting = false;

  DateTime? _dateNeeded;
  String _priority = 'normal';

  @override
  void dispose() {
    _subjectController.dispose();
    _materialNameController.dispose();
    _quantityController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold
    (
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Material Request',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SiteManagerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject for admin approval',
                        hintText: 'Example: Request for bond paper and printer ink',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a subject';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _materialNameController,
                      decoration: const InputDecoration(
                        labelText: 'Material Name',
                        hintText: 'Example: Cement',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter the material name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        hintText: 'Example: 100',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter the quantity';
                        final parsed = double.tryParse(v.replaceAll(',', ''));
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid quantity';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _purposeController,
                      decoration: const InputDecoration(
                        labelText: 'Purpose / Justification',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dateNeeded ?? now,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 2),
                        );
                        if (picked == null) return;
                        if (!mounted) return;
                        setState(() {
                          _dateNeeded = picked;
                        });
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date Needed',
                        ),
                        child: Text(
                          _dateNeeded == null
                              ? 'Select date'
                              : '${_dateNeeded!.year.toString().padLeft(4, '0')}-'
                                  '${_dateNeeded!.month.toString().padLeft(2, '0')}-'
                                  '${_dateNeeded!.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Priority',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNormal = _priority == 'normal';
                        final isUrgent = _priority == 'urgent';

                        return Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _priority = 'normal';
                                  });
                                },
                                icon: Icon(
                                  isNormal ? Icons.check : Icons.circle_outlined,
                                  size: 18,
                                ),
                                label: const Text('Normal'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      isNormal ? AppTheme.deepBlue : null,
                                  foregroundColor:
                                      isNormal ? Colors.white : null,
                                  side: BorderSide(
                                    color: isNormal
                                        ? AppTheme.deepBlue
                                        : Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _priority = 'urgent';
                                  });
                                },
                                icon: Icon(
                                  isUrgent ? Icons.check : Icons.circle_outlined,
                                  size: 18,
                                ),
                                label: const Text('Urgent'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor:
                                      isUrgent ? AppTheme.deepBlue : null,
                                  foregroundColor:
                                      isUrgent ? Colors.white : null,
                                  side: BorderSide(
                                    color: isUrgent
                                        ? AppTheme.deepBlue
                                        : Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 24),
              AppButton(
                text: 'Submit Request',
                onPressed: _isSubmitting ? null : _submit,
                isLoading: _isSubmitting,
                icon: Icons.send,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = AuthService.instance.currentUser;
    final projectId = user?.assignedProjects.isNotEmpty == true ? user!.assignedProjects.first : null;

    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No assigned project found for this user'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final now = DateTime.now().toIso8601String();
      final subject = _subjectController.text.trim();
      final materialName = _materialNameController.text.trim();
      final quantityText = _quantityController.text.trim();
      final parsedQuantity =
          double.tryParse(quantityText.replaceAll(',', ''));
      final purpose = _purposeController.text.trim();

      final requestId =
          'mr_${projectId}_${DateTime.now().millisecondsSinceEpoch.toString()}';

      String? projectName;
      try {
        final projectDoc = await FirebaseService.instance.projectsCollection.doc(projectId).get();
        if (projectDoc.exists) {
          final data = projectDoc.data() as Map<String, dynamic>?;
          projectName = (data?['name'] ?? '').toString();
        }
      } catch (_) {
        // Ignore and fall back to projectId only.
      }

      final payload = <String, dynamic>{
        'id': requestId,
        'subject': subject,
        'details': purpose,
        'materialName': materialName,
        'requestedQuantity': parsedQuantity,
        'requestedQuantityText': quantityText,
        'purpose': purpose,
        'dateNeeded': _dateNeeded?.toIso8601String(),
        'priority': _priority,
        'status': AppConstants.materialRequestPending,
        'projectId': projectId,
        'projectName': projectName ?? projectId,
        'createdBy': user?.id ?? user?.email,
        'createdByName': user?.displayName ?? '',
        'createdAt': now,
        'syncStatus': AppConstants.syncStatusPending,
        'geoTag': await GeoTagService.instance.captureGeoTag(),
      };

      await HiveService.instance.saveMaterialRequest(requestId, payload);

      final syncResult = await SyncService.instance.syncPendingData();

      final updated = HiveService.instance.getMaterialRequest(requestId);
      final status = (updated?['syncStatus']?.toString() ?? '').toLowerCase();
      final isSynced = status == AppConstants.syncStatusCompleted;

      await AuditLogService.instance.logAction(
        action: 'material_request_submitted',
        projectId: projectId,
        details: {
          'subject': subject,
          'materialName': materialName,
          'requestedQuantity': parsedQuantity,
          'priority': _priority,
          'projectName': projectName ?? projectId,
          'requestId': requestId,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSynced
              ? 'Material request submitted successfully'
              : (syncResult.message.isNotEmpty
                  ? syncResult.message
                  : 'Material request queued for sync when online')),
          backgroundColor:
              isSynced ? AppTheme.softGreen : AppTheme.warningOrange,
        ),
      );

      setState(() {
        _subjectController.clear();
        _materialNameController.clear();
        _quantityController.clear();
        _purposeController.clear();
        _dateNeeded = null;
        _priority = 'normal';
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit request: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}
