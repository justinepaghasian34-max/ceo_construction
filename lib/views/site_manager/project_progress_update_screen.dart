import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/common/app_button.dart';

class ProjectProgressUpdateScreen extends StatefulWidget {
  const ProjectProgressUpdateScreen({super.key});

  @override
  State<ProjectProgressUpdateScreen> createState() => _ProjectProgressUpdateScreenState();
}

class _ProjectProgressUpdateScreenState extends State<ProjectProgressUpdateScreen> {
  String? _projectId;
  final TextEditingController _projectNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  String _status = 'ongoing';
  double _progress = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentProject();
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProject() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.assignedProjects.isEmpty) {
      setState(() {
        _errorMessage = 'No assigned project found.';
        _isLoading = false;
      });
      return;
    }

    final projectId = user.assignedProjects.first;

    try {
      final doc = await FirebaseService.instance.projectsCollection.doc(projectId).get();
      if (!doc.exists) {
        setState(() {
          _errorMessage = 'Assigned project not found.';
          _isLoading = false;
        });
        return;
      }

      final data = doc.data() as Map<String, dynamic>? ?? {};
      final name = (data['name'] ?? '').toString();
      final location = (data['location'] ?? '').toString();
      final status = (data['status'] ?? 'ongoing').toString();
      final progressRaw = data['progressPercentage'];
      double progress;
      if (progressRaw is num) {
        progress = progressRaw.toDouble();
      } else if (progressRaw is String) {
        final cleaned = progressRaw.replaceAll('%', '').trim();
        progress = double.tryParse(cleaned) ?? 0.0;
      } else {
        progress = 0.0;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _projectId = projectId;
        _projectNameController.text = name;
        _locationController.text = location;
        _status = status.isEmpty ? 'ongoing' : status.toLowerCase();
        _progress = progress.clamp(0, 100);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Failed to load project.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    if (_projectId == null || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseService.instance.projectsCollection.doc(_projectId).update({
        'status': _status,
        'progressPercentage': _progress,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project progress updated'),
          backgroundColor: AppTheme.softGreen,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update progress: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );

      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_isLoading) {
      body = const Center(
        child: CircularProgressIndicator(),
      );
    } else if (_errorMessage != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.errorRed,
                ),
          ),
        ),
      );
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          TextField(
            controller: _projectNameController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Project name',
              filled: true,
              fillColor: AppTheme.lightGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Location',
              filled: true,
              fillColor: AppTheme.lightGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: InputDecoration(
              labelText: 'Status',
              filled: true,
              fillColor: AppTheme.lightGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: const [
              DropdownMenuItem(value: 'ongoing', child: Text('Ongoing')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _status = value;
              });
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                '${_progress.toStringAsFixed(0)} %',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          Slider(
            value: _progress,
            min: 0,
            max: 100,
            divisions: 20,
            label: '${_progress.toStringAsFixed(0)}%',
            activeColor: AppTheme.softGreen,
            onChanged: (value) {
              setState(() {
                _progress = value;
              });
            },
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Submit',
            onPressed: _isSaving ? null : _saveProgress,
            isLoading: _isSaving,
            width: double.infinity,
            backgroundColor: AppTheme.deepBlue,
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Project Progress Update',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: body,
    );
  }
}
