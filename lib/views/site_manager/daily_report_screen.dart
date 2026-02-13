import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../models/daily_report_model.dart';
import '../../models/attendance_model.dart';
import '../../services/hive_service.dart';
import '../../services/sync_service.dart';
import '../../services/firebase_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_button.dart';

class DailyReportScreen extends ConsumerStatefulWidget {
  const DailyReportScreen({super.key});

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
  final List<AttendanceRecord> _attendanceRecords = [];
  List<String> _attachmentUrls = [];
  bool _isLoading = false;
  bool _isUploadingImage = false;
  final TextEditingController _newWorkerNameController =
      TextEditingController();
  final TextEditingController _newWorkerPositionController =
      TextEditingController();
  final TextEditingController _newWorkerSkillController =
      TextEditingController();
  final TextEditingController _newWorkerRateController =
      TextEditingController();
  bool _newMonPresent = false;
  bool _newTuePresent = false;
  bool _newWedPresent = false;
  bool _newThuPresent = false;
  bool _newFriPresent = false;

  @override
  void initState() {
    super.initState();
    _loadDraftReport();
    _loadAttendanceForSelectedDate();
    _autoFillWeather();
  }

  Widget _buildAttachmentsSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Photos (Daily Progress)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_isUploadingImage)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!_isUploadingImage) ...[
                AppIconButton(
                  icon: Icons.photo_camera,
                  onPressed: () => _pickAndUploadImage(ImageSource.camera),
                  backgroundColor: AppTheme.softGreen.withValues(alpha: 0.1),
                  iconColor: AppTheme.softGreen,
                  tooltip: 'Capture photo',
                ),
                AppIconButton(
                  icon: Icons.photo_library,
                  onPressed: () => _pickAndUploadImage(ImageSource.gallery),
                  backgroundColor: AppTheme.deepBlue.withValues(alpha: 0.1),
                  iconColor: AppTheme.deepBlue,
                  tooltip: 'Add from gallery',
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_attachmentUrls.isEmpty)
            Text(
              'No photos attached yet',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
            )
          else
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachmentUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = _attachmentUrls[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.lightGray,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _attachmentUrls.removeAt(index);
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
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
        _attachmentUrls = List.from(todayDraft.attachmentUrls);
      });
    }
  }

  void _loadAttendanceForSelectedDate() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null || currentUser.assignedProjects.isEmpty) {
      return;
    }

    final projectId = currentUser.assignedProjects.first;
    final hive = HiveService.instance;

    final allForProject = hive.getAttendanceByProject(projectId);

    final matching = allForProject.where((attendance) {
      final date = attendance.attendanceDate;
      return attendance.recorderId == currentUser.id &&
          date.year == _selectedDate.year &&
          date.month == _selectedDate.month &&
          date.day == _selectedDate.day;
    }).toList();

    matching.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (matching.isEmpty) {
      setState(() {
        _attendanceRecords.clear();
        _newWorkerNameController.clear();
        _newWorkerPositionController.clear();
        _newWorkerSkillController.clear();
        _newWorkerRateController.clear();
        _newMonPresent = false;
        _newTuePresent = false;
        _newWedPresent = false;
        _newThuPresent = false;
        _newFriPresent = false;
      });
      return;
    }

    final latest = matching.first;

    setState(() {
      _attendanceRecords
        ..clear()
        ..addAll(latest.records);
      _newWorkerNameController.clear();
      _newWorkerPositionController.clear();
      _newWorkerSkillController.clear();
      _newWorkerRateController.clear();
      _newMonPresent = false;
      _newTuePresent = false;
      _newWedPresent = false;
      _newThuPresent = false;
      _newFriPresent = false;
    });
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

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();

    try {
      setState(() {
        _isUploadingImage = true;
      });

      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );

      if (pickedFile == null) {
        setState(() {
          _isUploadingImage = false;
        });
        return;
      }

      final bytes = await pickedFile.readAsBytes();
      final fileId = const Uuid().v4();
      final path = 'daily_reports/$fileId.jpg';

      final url = await FirebaseService.instance.uploadFile(
        path,
        bytes,
        contentType: 'image/jpeg',
      );

      setState(() {
        _attachmentUrls.add(url);
        _isUploadingImage = false;
      });
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              _buildAttendanceSection(),
              const SizedBox(height: 16),
              _buildWorkAccomplishmentsSection(),
              const SizedBox(height: 16),
              _buildAttachmentsSection(),
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
    );
  }

  Widget _buildAttendanceSection() {
    final positionOptions = <String>[
      'Engineer',
      'Foreman',
      'Skilled',
      'Non-Skilled',
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Attendance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _attendanceRecords.isEmpty
                    ? null
                    : showFullAttendanceTable,
                child: const Text('Full view'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.mediumGray,
              ),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Position')),
                DataColumn(label: Text('Rate')),
              ],
              rows: [
                DataRow(
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: TextField(
                          controller: _newWorkerNameController,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Name',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: TextField(
                          controller: _newWorkerPositionController,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Position',
                            border: InputBorder.none,
                            suffixIcon: PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down),
                              onSelected: (value) {
                                setState(() {
                                  _newWorkerPositionController.text = value;
                                });
                              },
                              itemBuilder: (context) {
                                return positionOptions
                                    .map(
                                      (p) => PopupMenuItem<String>(
                                        value: p,
                                        child: Text(p),
                                      ),
                                    )
                                    .toList();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      TextField(
                        controller: _newWorkerRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Rate',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) async {
                          setState(() {
                            appendPendingAttendanceFromNewRow();
                            _newWorkerNameController.clear();
                            _newWorkerPositionController.clear();
                            _newWorkerSkillController.clear();
                            _newWorkerRateController.clear();
                            _newMonPresent = false;
                            _newTuePresent = false;
                            _newWedPresent = false;
                            _newThuPresent = false;
                            _newFriPresent = false;
                          });

                          await _saveAttendanceDraftSnapshot();
                        },
                      ),
                    ),
                  ],
                ),
                ...List.generate(_attendanceRecords.length, (index) {
                  final record = _attendanceRecords[index];

                  return DataRow(
                    cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 200),
                          child: Text(
                            record.workerName,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        onTap: () => editAttendanceRecord(index),
                      ),
                      DataCell(
                        Text(
                          record.position,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      DataCell(
                        Text(
                          record.rate.toStringAsFixed(2),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showFullAttendanceTable() {
    String formatTime(DateTime? time) {
      if (time == null) return '--:--';
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Attendance (full view)',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 16,
                          headingTextStyle: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.mediumGray,
                              ),
                          columns: const [
                            DataColumn(label: Text('No.')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('Position')),
                            DataColumn(label: Text('Skill')),
                            DataColumn(label: Text('Work Rate')),
                            DataColumn(label: Text('AM In')),
                            DataColumn(label: Text('AM Out')),
                            DataColumn(label: Text('PM In')),
                            DataColumn(label: Text('PM Out')),
                            DataColumn(label: Text('Mon')),
                            DataColumn(label: Text('Tue')),
                            DataColumn(label: Text('Wed')),
                            DataColumn(label: Text('Thu')),
                            DataColumn(label: Text('Fri')),
                            DataColumn(label: Text('Note')),
                          ],
                          rows: [
                            for (var i = 0; i < _attendanceRecords.length; i++)
                              DataRow(
                                cells: [
                                  DataCell(Text('${i + 1}')),
                                  DataCell(
                                    Text(_attendanceRecords[i].workerName),
                                  ),
                                  DataCell(
                                    Text(_attendanceRecords[i].position),
                                  ),
                                  DataCell(
                                    Text(_attendanceRecords[i].workerType),
                                  ),
                                  DataCell(
                                    Text(
                                      _attendanceRecords[i].rate
                                          .toStringAsFixed(2),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTime(
                                        _attendanceRecords[i].amTimeIn,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTime(
                                        _attendanceRecords[i].amTimeOut,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTime(
                                        _attendanceRecords[i].pmTimeIn,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      formatTime(
                                        _attendanceRecords[i].pmTimeOut,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Checkbox(
                                      value: _attendanceRecords[i].monPresent,
                                      onChanged: (value) {
                                        setState(() {
                                          _attendanceRecords[i].monPresent =
                                              value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Checkbox(
                                      value: _attendanceRecords[i].tuePresent,
                                      onChanged: (value) {
                                        setState(() {
                                          _attendanceRecords[i].tuePresent =
                                              value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Checkbox(
                                      value: _attendanceRecords[i].wedPresent,
                                      onChanged: (value) {
                                        setState(() {
                                          _attendanceRecords[i].wedPresent =
                                              value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Checkbox(
                                      value: _attendanceRecords[i].thuPresent,
                                      onChanged: (value) {
                                        setState(() {
                                          _attendanceRecords[i].thuPresent =
                                              value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    Checkbox(
                                      value: _attendanceRecords[i].friPresent,
                                      onChanged: (value) {
                                        setState(() {
                                          _attendanceRecords[i].friPresent =
                                              value ?? false;
                                        });
                                      },
                                    ),
                                  ),
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 200,
                                      ),
                                      child: Text(
                                        _attendanceRecords[i].remarks ?? '',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateSection() {
    return AppCard(
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
    return AppCard(
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
    return AppCard(
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
    return AppCard(
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
    return AppCard(
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
      _loadAttendanceForSelectedDate();
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

  void editAttendanceRecord(int index) {
    _showWorkerAttendanceDetail(index);
  }

  void _showWorkerAttendanceDetail(int index) {
    final record = _attendanceRecords[index];

    final nameController = TextEditingController(text: record.workerName);
    final rateController = TextEditingController(
      text: record.rate > 0 ? record.rate.toStringAsFixed(2) : '',
    );
    final positionController = TextEditingController(text: record.position);
    final amInController = TextEditingController(
      text: record.amTimeIn != null
          ? '${record.amTimeIn!.hour.toString().padLeft(2, '0')}:${record.amTimeIn!.minute.toString().padLeft(2, '0')}'
          : '',
    );
    final amOutController = TextEditingController(
      text: record.amTimeOut != null
          ? '${record.amTimeOut!.hour.toString().padLeft(2, '0')}:${record.amTimeOut!.minute.toString().padLeft(2, '0')}'
          : '',
    );
    final pmInController = TextEditingController(
      text: record.pmTimeIn != null
          ? '${record.pmTimeIn!.hour.toString().padLeft(2, '0')}:${record.pmTimeIn!.minute.toString().padLeft(2, '0')}'
          : '',
    );
    final pmOutController = TextEditingController(
      text: record.pmTimeOut != null
          ? '${record.pmTimeOut!.hour.toString().padLeft(2, '0')}:${record.pmTimeOut!.minute.toString().padLeft(2, '0')}'
          : '',
    );

    final positionOptions = <String>[
      'Engineer',
      'Foreman',
      'Skilled',
      'Non-Skilled',
    ];

    DateTime? parseTime(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parts = trimmed.split(':');
      if (parts.length != 2) return null;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) return null;
      return DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        hour,
        minute,
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Worker Attendance',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Name',
                              style: Theme.of(sheetContext).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Position',
                              style: Theme.of(sheetContext).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: positionController,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                suffixIcon: PopupMenuButton<String>(
                                  icon: const Icon(Icons.arrow_drop_down),
                                  onSelected: (value) {
                                    setState(() {
                                      positionController.text = value;
                                    });
                                  },
                                  itemBuilder: (context) {
                                    return positionOptions
                                        .map(
                                          (p) => PopupMenuItem<String>(
                                            value: p,
                                            child: Text(p),
                                          ),
                                        )
                                        .toList();
                                  },
                                ),
                              ),
                              style: Theme.of(
                                sheetContext,
                              ).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rate',
                              style: Theme.of(sheetContext).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: rateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      headingTextStyle: Theme.of(sheetContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mediumGray,
                          ),
                      columns: const [
                        DataColumn(label: Text('Day')),
                        DataColumn(label: Text('Present')),
                        DataColumn(label: Text('Time in (AM)')),
                        DataColumn(label: Text('Time out (AM)')),
                        DataColumn(label: Text('Time in (PM)')),
                        DataColumn(label: Text('Time out (PM)')),
                      ],
                      rows: [
                        DataRow(
                          cells: [
                            const DataCell(Text('Monday')),
                            DataCell(
                              Checkbox(
                                value: record.monPresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].monPresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        DataRow(
                          cells: [
                            const DataCell(Text('Tuesday')),
                            DataCell(
                              Checkbox(
                                value: record.tuePresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].tuePresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        DataRow(
                          cells: [
                            const DataCell(Text('Wednesday')),
                            DataCell(
                              Checkbox(
                                value: record.wedPresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].wedPresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        DataRow(
                          cells: [
                            const DataCell(Text('Thursday')),
                            DataCell(
                              Checkbox(
                                value: record.thuPresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].thuPresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        DataRow(
                          cells: [
                            const DataCell(Text('Friday')),
                            DataCell(
                              Checkbox(
                                value: record.friPresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].friPresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        DataRow(
                          cells: [
                            const DataCell(Text('Saturday')),
                            DataCell(
                              Checkbox(
                                value: record.satPresent,
                                onChanged: (value) {
                                  setState(() {
                                    _attendanceRecords[index].satPresent =
                                        value ?? false;
                                  });
                                },
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: amOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmInController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            DataCell(
                              TextField(
                                controller: pmOutController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '--:--',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          removeAttendanceRecord(index);
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Delete'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final amIn = parseTime(amInController.text);
                          final amOut = parseTime(amOutController.text);
                          final pmIn = parseTime(pmInController.text);
                          final pmOut = parseTime(pmOutController.text);

                          double computedHours = 0;
                          if (amIn != null && amOut != null) {
                            computedHours +=
                                amOut.difference(amIn).inMinutes / 60.0;
                          }
                          if (pmIn != null && pmOut != null) {
                            computedHours +=
                                pmOut.difference(pmIn).inMinutes / 60.0;
                          }

                          final newName = nameController.text.trim();
                          final newPosition = positionController.text.trim();

                          setState(() {
                            if (newName.isNotEmpty) {
                              _attendanceRecords[index].workerName = newName;
                            }
                            if (newPosition.isNotEmpty) {
                              _attendanceRecords[index].position = newPosition;
                            }
                            _attendanceRecords[index].rate =
                                double.tryParse(rateController.text.trim()) ??
                                _attendanceRecords[index].rate;
                            _attendanceRecords[index].amTimeIn = amIn;
                            _attendanceRecords[index].amTimeOut = amOut;
                            _attendanceRecords[index].pmTimeIn = pmIn;
                            _attendanceRecords[index].pmTimeOut = pmOut;
                            _attendanceRecords[index].hoursWorked =
                                computedHours;
                          });
                          final saveFuture = _saveAttendanceDraftSnapshot();
                          Navigator.of(sheetContext).pop();
                          await saveFuture;
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void removeAttendanceRecord(int index) {
    setState(() {
      _attendanceRecords.removeAt(index);
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

  void appendPendingAttendanceFromNewRow() {
    final name = _newWorkerNameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    final position = _newWorkerPositionController.text.trim();
    final skill = _newWorkerSkillController.text.trim();
    final rate = double.tryParse(_newWorkerRateController.text.trim()) ?? 0.0;

    final anyPresent =
        _newMonPresent ||
        _newTuePresent ||
        _newWedPresent ||
        _newThuPresent ||
        _newFriPresent;

    final newRecord = AttendanceRecord(
      workerId: const Uuid().v4(),
      workerName: name,
      position: position,
      isPresent: anyPresent,
      workerType: skill.isEmpty ? 'labor' : skill,
      rate: rate,
      monPresent: _newMonPresent,
      tuePresent: _newTuePresent,
      wedPresent: _newWedPresent,
      thuPresent: _newThuPresent,
      friPresent: _newFriPresent,
    );

    _attendanceRecords.add(newRecord);
  }

  Future<void> _saveAttendanceDraftSnapshot() async {
    if (_attendanceRecords.isEmpty) {
      return;
    }

    UserModel? currentUser = ref.read(currentUserProvider);

    if (currentUser == null || currentUser.assignedProjects.isEmpty) {
      final refreshed = await AuthService.instance.refreshUserData();
      if (refreshed) {
        ref.invalidate(currentUserProvider);
        currentUser = ref.read(currentUserProvider);
      }
    }

    if (currentUser == null || currentUser.assignedProjects.isEmpty) {
      return;
    }

    final String projectId = currentUser.assignedProjects.first;
    final String reporterId = currentUser.id;

    final attendance = AttendanceModel(
      id: const Uuid().v4(),
      projectId: projectId,
      recorderId: reporterId,
      attendanceDate: _selectedDate,
      records: List<AttendanceRecord>.from(_attendanceRecords),
      status: 'draft',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      syncStatus: 'pending',
    );

    await HiveService.instance.saveAttendance(attendance);
  }

  Future<void> saveDraft() async {
    if (!_formKey.currentState!.validate()) return;

    appendPendingAttendanceFromNewRow();

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
        attachmentUrls: _attachmentUrls,
        status: 'draft',
        remarks: _remarksController.text.isEmpty
            ? null
            : _remarksController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await HiveService.instance.saveDailyReport(report);

      if (_attendanceRecords.isNotEmpty) {
        final attendance = AttendanceModel(
          id: const Uuid().v4(),
          projectId: projectId,
          recorderId: reporterId,
          attendanceDate: _selectedDate,
          records: _attendanceRecords,
          status: 'draft',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        );

        await HiveService.instance.saveAttendance(attendance);
      }

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

    appendPendingAttendanceFromNewRow();

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
        attachmentUrls: _attachmentUrls,
        status: 'submitted',
        remarks: _remarksController.text.isEmpty
            ? null
            : _remarksController.text,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: 'pending',
      );

      await HiveService.instance.saveDailyReport(report);

      if (_attendanceRecords.isNotEmpty) {
        final attendance = AttendanceModel(
          id: const Uuid().v4(),
          projectId: projectId,
          recorderId: reporterId,
          attendanceDate: _selectedDate,
          records: _attendanceRecords,
          status: 'submitted',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          syncStatus: 'pending',
        );

        await HiveService.instance.saveAttendance(attendance);
      }

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
    _newWorkerNameController.dispose();
    _newWorkerPositionController.dispose();
    _newWorkerSkillController.dispose();
    _newWorkerRateController.dispose();
    super.dispose();
  }
}
