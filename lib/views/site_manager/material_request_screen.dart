import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/audit_log_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';

class MaterialRequestScreen extends StatefulWidget {
  const MaterialRequestScreen({super.key});

  @override
  State<MaterialRequestScreen> createState() => _MaterialRequestScreenState();
}

class _MaterialRequestScreenState extends State<MaterialRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _detailsController = TextEditingController();

  bool _isSubmitting = false;
  bool _isUploadingImage = false;
  String? _attachmentUrl;

  @override
  void dispose() {
    _subjectController.dispose();
    _detailsController.dispose();
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
              AppCard(
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
                        hintText: 'Example: Requesting additional cement bags',
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
                      controller: _detailsController,
                      decoration: const InputDecoration(
                        labelText: 'Details / justification',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Receipt / delivery photo',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (_isUploadingImage)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_attachmentUrl == null)
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              text: 'Add Photo',
                              onPressed: _isUploadingImage ? null : () => _pickAndUploadImage(ImageSource.camera),
                              icon: Icons.photo_camera,
                              isOutlined: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AppButton(
                              text: 'From Gallery',
                              onPressed: _isUploadingImage ? null : () => _pickAndUploadImage(ImageSource.gallery),
                              icon: Icons.photo_library,
                              isOutlined: true,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 3 / 2,
                              child: Image.network(
                                _attachmentUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppTheme.lightGray,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _isUploadingImage
                                  ? null
                                  : () {
                                      setState(() {
                                        _attachmentUrl = null;
                                      });
                                    },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove photo'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
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

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();

    try {
      setState(() {
        _isUploadingImage = true;
      });

      final picked = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (picked == null) {
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      final Uint8List bytes = await picked.readAsBytes();
      final id = const Uuid().v4();
      final path = 'material_requests/$id.jpg';

      final url = await FirebaseService.instance.uploadFile(
        path,
        bytes,
        contentType: 'image/jpeg',
      );

      setState(() {
        _attachmentUrl = url;
        _isUploadingImage = false;
      });
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
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
      final details = _detailsController.text.trim();
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

      await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .collection('material_requests')
          .add({
        'subject': subject,
        'details': details,
        'attachmentUrl': _attachmentUrl,
        'status': AppConstants.materialRequestPending,
        'projectId': projectId,
        'projectName': projectName ?? projectId,
        'createdBy': user?.id ?? user?.email,
        'createdByName': user?.displayName ?? '',
        'createdAt': now,
      });

      await AuditLogService.instance.logAction(
        action: 'material_request_submitted',
        projectId: projectId,
        details: {
          'subject': subject,
          'projectName': projectName ?? projectId,
          'hasAttachment': _attachmentUrl != null,
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material request submitted for admin approval'),
          backgroundColor: AppTheme.softGreen,
        ),
      );

      Navigator.pop(context);
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
