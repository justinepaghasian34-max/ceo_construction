import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';

class AiAssistantChatScreen extends StatefulWidget {
  const AiAssistantChatScreen({super.key});

  @override
  State<AiAssistantChatScreen> createState() => _AiAssistantChatScreenState();
}

class _AiAssistantChatScreenState extends State<AiAssistantChatScreen> {
  final _messageController = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageName;

  bool _aiIsRunning = false;
  double? _aiProgressPercent;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  Future<double?> _estimateProgressPercent({
    required String projectId,
    required String projectName,
    required String? imageUrl,
    required String? storagePath,
    required String? fileName,
    required String analysisDocId,
  }) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final idToken = await firebaseUser?.getIdToken(true);
      final callable = FirebaseFunctions.instance.httpsCallable('estimateProgressPercent');
      final res = await callable.call({
        'projectId': projectId,
        'projectName': projectName,
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'fileName': fileName,
        'analysisDocId': analysisDocId,
        'idToken': idToken,
      });

      final data = (res.data is Map) ? (res.data as Map).cast<String, dynamic>() : <String, dynamic>{};
      final v = data['progressPercent'];
      if (v is num) {
        return v.toDouble().clamp(0, 100);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final user = AuthService.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in.')),
      );
      return;
    }

    if (user.assignedProjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No project assigned.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final msg = _messageController.text.trim();
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please attach a site progress image.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final projectId = user.assignedProjects.first;
      final projectDoc = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      final projectData =
          (projectDoc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};
      final projectName = (projectData['name'] ?? projectData['projectName'] ?? '')
          .toString()
          .trim();

      final now = DateTime.now().millisecondsSinceEpoch;
      final safeName = (_imageName ?? 'progress.jpg').replaceAll(' ', '_');
      final storagePath = 'progress_reports/$projectId/${user.id}/$now-$safeName';

      final imageUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        _imageBytes!,
        contentType: 'image/jpeg',
      );

      final createdAt = Timestamp.now();

      final docRef = await FirebaseService.instance.aiAnalysisCollection.add({
        'kind': 'govtrack_progress_report',
        'createdAt': createdAt,
        'projectId': projectId,
        'projectName': projectName.isEmpty ? 'Unknown Project' : projectName,
        'progressPercent': null,
        'aiStatus': 'pending',
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'fileName': safeName,
        'submittedById': user.id,
        'submittedByName': '${user.firstName} ${user.lastName}'.trim(),
        'submittedByEmail': user.email,
        'assignedSiteManagerName': '${user.firstName} ${user.lastName}'.trim(),
        'assignedSiteManagerEmail': user.email,
        'analysis': {
          'summary': msg,
          'imageProvided': true,
        },
      });

      if (!mounted) return;

      setState(() {
        _aiIsRunning = true;
        _aiProgressPercent = null;
      });

      final estimated = await _estimateProgressPercent(
        projectId: projectId,
        projectName: projectName.isEmpty ? 'Unknown Project' : projectName,
        imageUrl: imageUrl,
        storagePath: storagePath,
        fileName: safeName,
        analysisDocId: docRef.id,
      );

      if (estimated != null) {
        await docRef.update({
          'progressPercent': estimated,
          'aiStatus': 'done',
          'aiUpdatedAt': Timestamp.now(),
        });
      } else {
        await docRef.update({
          'aiStatus': 'failed',
          'aiUpdatedAt': Timestamp.now(),
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            estimated == null
                ? 'Uploaded. AI progress is pending.'
                : 'Uploaded. AI progress: ${estimated.toStringAsFixed(0)}%',
          ),
          backgroundColor: AppTheme.softGreen,
        ),
      );

      setState(() {
        _messageController.clear();
        _imageBytes = null;
        _imageName = null;
        _aiIsRunning = false;
        _aiProgressPercent = estimated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Submit failed: $e'),
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

  Widget _glowChatCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppTheme.deepBlue.withValues(alpha: 0.24),
            blurRadius: 36,
            spreadRadius: 6,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppTheme.deepBlue.withValues(alpha: 0.25),
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aiText = _aiIsRunning
        ? 'AI: Analyzing...'
        : (_aiProgressPercent == null
            ? 'AI: Pending'
            : 'AI: ${_aiProgressPercent!.toStringAsFixed(0)}%');

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Assistant Chat'),
      ),
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.lightGray,
                AppTheme.deepBlue.withValues(alpha: 0.08),
                AppTheme.lightGray,
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _glowChatCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'AI Assistant Chat',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.deepBlue,
                                    ),
                              ),
                            ),
                            const SizedBox.shrink(),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppTheme.deepBlue.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            children: [
                              TextField(
                                controller: _messageController,
                                maxLines: 5,
                                minLines: 4,
                                decoration: InputDecoration(
                                  hintText: 'Describe your question..........',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              if (_imageBytes != null) ...[
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.memory(
                                      _imageBytes!,
                                      height: 160,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ],
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    _ActionIconButton(
                                      icon: Icons.emoji_emotions_outlined,
                                      onPressed: _isSubmitting ? null : () {},
                                    ),
                                    const SizedBox(width: 6),
                                    _ActionIconButton(
                                      icon: Icons.attach_file,
                                      onPressed: _isSubmitting ? null : () {},
                                    ),
                                    const SizedBox(width: 6),
                                    _ActionIconButton(
                                      icon: Icons.image_outlined,
                                      onPressed: _isSubmitting ? null : _pickImage,
                                    ),
                                    const SizedBox(width: 6),
                                    _ActionIconButton(
                                      icon: Icons.mic_none,
                                      onPressed: _isSubmitting ? null : () {},
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.deepBlue.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        aiText,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: AppTheme.deepBlue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      onPressed: _isSubmitting ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.deepBlue,
                                        foregroundColor: AppTheme.white,
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(14),
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.arrow_upward),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _ActionIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: AppTheme.mediumGray),
      splashRadius: 20,
      tooltip: null,
    );
  }
}
