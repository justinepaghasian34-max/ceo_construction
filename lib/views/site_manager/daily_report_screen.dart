import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/daily_report_model.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import 'widgets/site_manager_bottom_nav.dart';
import 'widgets/site_manager_card.dart';
import '../../widgets/common/app_button.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  final bool showBottomNav;
  final bool showBack;

  const DailyReportScreen({
    super.key,
    this.showBottomNav = false,
    this.showBack = true,
  });

  @override
  ConsumerState<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends ConsumerState<DailyReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weatherController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _remarksController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  List<WorkAccomplishment> _workAccomplishments = [];
  List<String> _issues = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDraftReport();
    _autoFillWeather();
  }

  void _loadDraftReport() {
    // Load any existing draft for today
    final reports = HiveService.instance.getAllDailyReports();
    final todayDraft = reports
        .where(
          (report) =>
              report.reportDate.day == DateTime.now().day &&
              report.reportDate.month == DateTime.now().month &&
              report.reportDate.year == DateTime.now().year &&
              report.status == 'draft',
        )
        .firstOrNull;

    if (todayDraft != null) {
      setState(() {
        _weatherController.text = todayDraft.weatherCondition;
        _temperatureController.text = todayDraft.temperatureC.toString();
        _remarksController.text = todayDraft.remarks ?? '';
        _workAccomplishments = List.from(todayDraft.workAccomplishments);
        _issues = List.from(todayDraft.issues);
      });
    }
  }

  /// Automatically fill weather and temperature using a weather API.
  ///
  /// NOTE: You must provide a real API key and location for this to work.
  /// If the key is left as the placeholder, this method will do nothing
  /// and the user can still enter weather manually.
  Future<void> _autoFillWeather() async {
    // Do not override if user already entered values (e.g. from a draft).
    if (_weatherController.text.isNotEmpty &&
        _temperatureController.text.isNotEmpty) {
      return;
    }

    const String apiKey = '36d74affc54853e817cac837ebaf6d8a';
    const String city =
        'Oroquieta City,PH'; // Set to your actual city, e.g. 'Davao,PH'

    // Avoid making failing calls if the developer hasn't configured the key/city yet.
    if (apiKey.isEmpty || city.isEmpty) {
      return;
    }

    try {
      final dio = Dio();
      final response = await dio.get(
        'https://api.openweathermap.org/data/2.5/weather',
        queryParameters: {'q': city, 'appid': apiKey, 'units': 'metric'},
      );

      if (!mounted) return;

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return;

      final weatherList = data['weather'] as List<dynamic>?;
      final main = data['main'] as Map<String, dynamic>?;
      if (weatherList == null || weatherList.isEmpty || main == null) return;

      final description = (weatherList.first['description'] ?? '').toString();
      final tempValue = (main['temp'] ?? 0);
      final double temp = tempValue is num ? tempValue.toDouble() : 0.0;

      setState(() {
        if (_weatherController.text.isEmpty) {
          _weatherController.text = description;
        }
        if (_temperatureController.text.isEmpty) {
          _temperatureController.text = temp.toStringAsFixed(1);
        }
      });
    } catch (_) {
      // Silently ignore failures; user can still enter weather manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              )
            : null,
        title: const Text(
          'Daily Report',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          SyncButton(
            onPressed: () => SyncService.instance.syncPendingData(),
            pendingCount: SyncService.instance
                .getSyncStats()
                .pendingDailyReports,
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              _buildDateSection(),
              const SizedBox(height: 16),
              _buildWeatherSection(),
              const SizedBox(height: 16),
              _buildWorkAccomplishmentsSection(),
              const SizedBox(height: 16),
              _buildIssuesSection(),
              const SizedBox(height: 16),
              _buildRemarksSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
      bottomNavigationBar:
          widget.showBottomNav ? const SiteManagerBottomNav(currentIndex: 1) : null,
    );
  }

  Widget _buildDateSection() {
    return SiteManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Report Date',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: selectDate,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.mediumGray.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: AppTheme.deepBlue),
                  const SizedBox(width: 12),
                  Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down, color: AppTheme.mediumGray),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherSection() {
    return SiteManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: AppTheme.warningOrange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Weather today',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                'auto',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _weatherController,
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    hintText: 'Sunny, Cloudy, Rainy',
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter weather condition';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _temperatureController,
                  decoration: const InputDecoration(
                    labelText: 'Temp (°C)',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Required';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Invalid number';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkAccomplishmentsSection() {
    return SiteManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Work Accomplishments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.add,
                onPressed: addWorkAccomplishment,
                backgroundColor: AppTheme.softGreen.withValues(alpha: 0.1),
                iconColor: AppTheme.softGreen,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_workAccomplishments.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.construction,
                    size: 48,
                    color: AppTheme.mediumGray,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No work accomplishments added yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_workAccomplishments.length, (index) {
              final work = _workAccomplishments[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            work.description,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        AppIconButton(
                          icon: Icons.edit,
                          onPressed: () => editWorkAccomplishment(index),
                          iconColor: AppTheme.deepBlue,
                        ),
                        AppIconButton(
                          icon: Icons.delete,
                          onPressed: () => removeWorkAccomplishment(index),
                          iconColor: AppTheme.errorRed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'WBS: ${work.wbsCode}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Qty: ${work.quantityAccomplished} ${work.unit}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${work.percentageComplete.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppTheme.softGreen,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildIssuesSection() {
    return SiteManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Issues & Concerns',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AppIconButton(
                icon: Icons.add,
                onPressed: addIssue,
                backgroundColor: AppTheme.warningOrange.withValues(alpha: 0.1),
                iconColor: AppTheme.warningOrange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_issues.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 48,
                    color: AppTheme.softGreen,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No issues reported',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mediumGray,
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_issues.length, (index) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.warningOrange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_outlined,
                      color: AppTheme.warningOrange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _issues[index],
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.delete,
                      onPressed: () => removeIssue(index),
                      iconColor: AppTheme.errorRed,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRemarksSection() {
    return SiteManagerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Additional Remarks',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _remarksController,
            decoration: const InputDecoration(
              hintText: 'Any additional notes or observations...',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                text: 'Save Offline',
                onPressed: _isLoading ? null : saveDraft,
                isOutlined: true,
                icon: Icons.save,
                isLoading: _isLoading,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppButton(
                text: 'Submit Online',
                onPressed: _isLoading ? null : submitReport,
                icon: Icons.cloud_upload,
                isLoading: _isLoading,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  void addWorkAccomplishment() {
    showWorkAccomplishmentDialog();
  }

  void editWorkAccomplishment(int index) {
    showWorkAccomplishmentDialog(
      workAccomplishment: _workAccomplishments[index],
      index: index,
    );
  }

  void removeWorkAccomplishment(int index) {
    setState(() {
      _workAccomplishments.removeAt(index);
    });
  }

  void addIssue() {
    showIssueDialog();
  }

  void removeIssue(int index) {
    setState(() {
      _issues.removeAt(index);
    });
  }

  void showWorkAccomplishmentDialog({
    WorkAccomplishment? workAccomplishment,
    int? index,
  }) {
    final wbsController = TextEditingController(
      text: workAccomplishment?.wbsCode ?? '',
    );
    final descriptionController = TextEditingController(
      text: workAccomplishment?.description ?? '',
    );
    final unitController = TextEditingController(
      text: workAccomplishment?.unit ?? '',
    );
    final quantityController = TextEditingController(
      text: workAccomplishment?.quantityAccomplished.toString() ?? '',
    );
    final percentageController = TextEditingController(
      text: workAccomplishment?.percentageComplete.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          workAccomplishment == null
              ? 'Add Work Accomplishment'
              : 'Edit Work Accomplishment',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: wbsController,
                decoration: const InputDecoration(labelText: 'WBS Code'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: quantityController,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: unitController,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: percentageController,
                decoration: const InputDecoration(
                  labelText: 'Percentage Complete',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final work = WorkAccomplishment(
                id: workAccomplishment?.id ?? const Uuid().v4(),
                wbsCode: wbsController.text,
                description: descriptionController.text,
                unit: unitController.text,
                quantityAccomplished:
                    double.tryParse(quantityController.text) ?? 0,
                percentageComplete:
                    double.tryParse(percentageController.text) ?? 0,
              );

              setState(() {
                if (index != null) {
                  _workAccomplishments[index] = work;
                } else {
                  _workAccomplishments.add(work);
                }
              });

              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void showIssueDialog() {
    final issueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Issue'),
        content: TextField(
          controller: issueController,
          decoration: const InputDecoration(
            labelText: 'Issue Description',
            hintText: 'Describe the issue or concern...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (issueController.text.isNotEmpty) {
                setState(() {
                  _issues.add(issueController.text);
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> saveDraft() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      UserModel? currentUser = ref.read(currentUserProvider);

      // If no assignment is found locally, try to refresh from Firestore in
      // case Admin has just assigned this Site Manager to a project.
      if (currentUser == null || currentUser.assignedProjects.isEmpty) {
        final refreshed = await AuthService.instance.refreshUserData();
        if (refreshed) {
          ref.invalidate(currentUserProvider);
          currentUser = ref.read(currentUserProvider);
        }
      }

      if (currentUser == null || currentUser.assignedProjects.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No assigned project found for current user'),
              backgroundColor: AppTheme.errorRed,
            ),
          );
        }
        return;
      }

      final String projectId = currentUser.assignedProjects.first;
      final String reporterId = currentUser.id;

      final report = DailyReportModel(
        id: const Uuid().v4(),
        projectId: projectId,
        reporterId: reporterId,
        reportDate: _selectedDate,
        weatherCondition: _weatherController.text,
        temperatureC: double.tryParse(_temperatureController.text) ?? 0,
        workAccomplishments: _workAccomplishments,
        issues: _issues,
        attachmentUrls: const <String>[],
        status: 'draft',
        remarks: _remarksController.text.isEmpty
            ? null
            : _remarksController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await HiveService.instance.saveDailyReport(report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report saved offline'),
            backgroundColor: AppTheme.softGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving report: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      UserModel? currentUser = ref.read(currentUserProvider);

      // If no assignment is found locally, try to refresh from Firestore in
      // case Admin has just assigned this Site Manager to a project.
      if (currentUser == null || currentUser.assignedProjects.isEmpty) {
        final refreshed = await AuthService.instance.refreshUserData();
        if (refreshed) {
          ref.invalidate(currentUserProvider);
          currentUser = ref.read(currentUserProvider);
        }
      }

      if (currentUser == null || currentUser.assignedProjects.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No assigned project found for current user'),
              backgroundColor: AppTheme.errorRed,
            ),
          );
        }
        return;
      }

      final String projectId = currentUser.assignedProjects.first;
      final String reporterId = currentUser.id;

      final report = DailyReportModel(
        id: const Uuid().v4(),
        projectId: projectId,
        reporterId: reporterId,
        reportDate: _selectedDate,
        weatherCondition: _weatherController.text,
        temperatureC: double.tryParse(_temperatureController.text) ?? 0,
        workAccomplishments: _workAccomplishments,
        issues: _issues,
        attachmentUrls: const <String>[],
        status: 'submitted',
        remarks: _remarksController.text.isEmpty
            ? null
            : _remarksController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );

      await HiveService.instance.saveDailyReport(report);

      // Try to sync immediately
      final syncResult = await SyncService.instance.syncPendingData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncResult.success
                  ? 'Report submitted successfully'
                  : 'Report queued for sync when online',
            ),
            backgroundColor: syncResult.success
                ? AppTheme.softGreen
                : AppTheme.warningOrange,
          ),
        );

        if (syncResult.success) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting report: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _weatherController.dispose();
    _temperatureController.dispose();
    _remarksController.dispose();
    super.dispose();
  }
}
