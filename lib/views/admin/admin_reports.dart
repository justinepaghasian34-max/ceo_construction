import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/daily_report_model.dart';
import '../../services/firebase_service.dart';
import '../../widgets/common/status_chip.dart';
import 'widgets/admin_bottom_nav.dart';

class AdminReports extends StatelessWidget {
  const AdminReports({super.key});

  @override
  Widget build(BuildContext context) {
    return _AiDashboard(
      onOpenDailyReport: (report) => _showReportDetailsDialog(context, report),
    );
  }

  void _showReportDetailsDialog(BuildContext context, DailyReportModel report) {
    final date = report.reportDate;
    final dateText = '${date.day}/${date.month}/${date.year}';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Daily Report - $dateText'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description,
                        color: AppTheme.deepBlue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Project: ${report.projectId}',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Reporter: ${report.reporterId}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.mediumGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ReportStatusChip(
                        reportStatus: report.status,
                        isSmall: true,
                      ),
                      const SizedBox(width: 4),
                      SyncStatusChip(
                        syncStatus: report.syncStatus,
                        isSmall: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Weather & Conditions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Weather: ${report.weatherCondition}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Temperature: ${report.temperatureC.toStringAsFixed(1)}°C',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Work Accomplishments (${report.workAccomplishments.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (report.workAccomplishments.isEmpty)
                    Text(
                      'No work items recorded.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    )
                  else
                    Column(
                      children: [
                        for (final item in report.workAccomplishments) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.lightGray,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.description,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'WBS: ${item.wbsCode} • ${item.quantityAccomplished} ${item.unit}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Progress: ${item.percentageComplete.toStringAsFixed(1)}%',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (item.remarks != null && item.remarks!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Remarks: ${item.remarks}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Issues (${report.issues.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (report.issues.isEmpty)
                    Text(
                      'No issues reported.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                          ),

                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final issue in report.issues) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(
                                child: Text(
                                  issue,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Attachments (${report.attachmentUrls.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (report.attachmentUrls.isEmpty)
                    Text(
                      'No attachments.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final url in report.attachmentUrls)
                          SizedBox(
                            width: 120,
                            height: 90,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
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
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (report.remarks != null && report.remarks!.trim().isNotEmpty) ...[
                    Text(
                      'Admin Remarks',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report.remarks!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

enum _AiNavItem {
  commandCenter,
  intelligenceChat,
  aiDailyProgress,
  activeAlerts,
  validationReports,
  auditLogs,
}

class _AiDashboard extends StatefulWidget {
  const _AiDashboard({required this.onOpenDailyReport});

  final ValueChanged<DailyReportModel> onOpenDailyReport;

  @override
  State<_AiDashboard> createState() => _AiDashboardState();
}

class _AiDashboardState extends State<_AiDashboard> {
  static const Color _navBgTop = Color(0xFF0B1220);
  static const Color _navBgBottom = Color(0xFF0A1325);
  static const Color _navBorder = Color(0xFF16233A);
  static const Color _navText = Color(0xFFCBD5E1);
  static const Color _navMuted = Color(0xFF94A3B8);
  static const Color _navActiveBg = Color(0xFF111C33);
  static const Color _navActiveAccent = Color(0xFF2563EB);

  static const Color _pageBg = Color(0xFFF6F8FB);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _title = Color(0xFF0F172A);
  static const Color _subtitle = Color(0xFF64748B);
  static const Color _blue = Color(0xFF2563EB);

  static const List<BoxShadow> _shadow = [
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  _AiNavItem _selected = _AiNavItem.commandCenter;
  int _topTabIndex = 0;

  bool _isVerifying = false;
  bool _isAnalyzing = false;

  String? _selectedProjectId;
  String? _selectedProjectName;

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

  Map<String, dynamic>? _lastAnalysis;

  final TextEditingController _chatController = TextEditingController();
  final List<_ChatMessage> _messages = <_ChatMessage>[
    const _ChatMessage(
      isUser: false,
      text: 'I can help you monitor infrastructure projects. You can ask me to:\n\n'
          '• Identify delayed projects\n'
          '• Analyze specific sites\n'
          '• Show a risk heatmap of all active contracts\n'
          '• Verify recent milestone submissions',
    ),
  ];

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GovSidebar(
            selected: _selected,
            onSelect: (v) => setState(() => _selected = v),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopHeader(
                  tabIndex: _topTabIndex,
                  onTabChange: (i) => setState(() => _topTabIndex = i),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _buildBody(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNavBar(current: AdminNavItem.aiReports),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_selected) {
      case _AiNavItem.commandCenter:
        return _buildCommandCenter(context);
      case _AiNavItem.intelligenceChat:
        return _buildChat(context);
      case _AiNavItem.aiDailyProgress:
        return _buildAiDailyProgress(context);
      case _AiNavItem.activeAlerts:
        return _buildPlaceholder(context, 'Active Alerts', 'No active alerts at this time.');
      case _AiNavItem.validationReports:
        return _buildValidationReportsPanel(context);
      case _AiNavItem.auditLogs:
        return _buildPlaceholder(context, 'Audit Logs', 'Audit log view placeholder.');
    }
  }

  Widget _buildCommandCenter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageTitle(
          title: 'Executive Command Center',
          subtitle: 'Real-time Infrastructure Monitoring • Province of Batangas',
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _PillTabs(
              index: _topTabIndex,
              onChange: (i) => setState(() => _topTabIndex = i),
            ),
            const Spacer(),
            _IconCircleButton(icon: Icons.search, onTap: () {}),
            const SizedBox(width: 10),
            _IconCircleButton(icon: Icons.notifications_none, onTap: () {}),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 1200 ? 2 : 1,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.4,
            children: const [
              _MetricCard(
                icon: Icons.monitor_heart_outlined,
                title: 'TOTAL ACTIVE PROJECTS',
                value: '24',
                subtitle: '3 Completed this month',
                deltaText: '5.2%',
                deltaUp: true,
              ),
              _MetricCard(
                icon: Icons.attach_money,
                title: 'BUDGET UTILIZATION',
                value: '₱ 142.5M',
                subtitle: '85% of allocated funds',
                deltaText: '2.1%',
                deltaUp: true,
              ),
              _MetricCard(
                icon: Icons.warning_amber_rounded,
                title: 'PROJECTS AT RISK',
                value: '3',
                subtitle: 'Requires immediate attention',
                deltaText: '12%',
                deltaUp: false,
                tone: _MetricTone.risk,
              ),
              _MetricCard(
                icon: Icons.trending_up,
                title: 'AVG. COMPLETION RATE',
                value: '68%',
                subtitle: 'Across all active sites',
                deltaText: '8.4%',
                deltaUp: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChat(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageTitle(
          title: 'Intelligence Chat',
          subtitle: 'Ask GovTrack AI about projects, budgets, or milestones.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _GovChatBubble(message: _messages[index]),
                  ),
                ),
                const Divider(height: 1, color: _border),
                _ChatComposer(
                  controller: _chatController,
                  onSend: _sendChat,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'GovTrack AI uses simulated structural confidence scores. Always verify critical alerts on-site.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _subtitle),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildAiDailyProgress(BuildContext context) {
    return ListView(
      children: [
        const _PageTitle(
          title: 'AI Daily Progress',
          subtitle: 'Upload site photos for instant AI structural analysis and progress verification.',
        ),
        const SizedBox(height: 16),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'SELECT PROJECT',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _subtitle,
                      ),
                ),
                const SizedBox(height: 10),
                _buildProjectDropdown(context),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UploadDropzone(
                  bytes: _selectedImageBytes,
                  onPick: _pickDailyProgressImage,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: _isAnalyzing ? null : _analyzeDailyProgress,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Analyze Progress', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_lastAnalysis != null) ...[
          const SizedBox(height: 18),
          _GovTrackReportCard(
            projectName: _selectedProjectName ?? 'Selected Project',
            analysis: _lastAnalysis!,
          ),
        ],
      ],
    );
  }

  Widget _buildValidationReportsPanel(BuildContext context) {
    final list = StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('ai_verifications')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _EmptyHint(text: 'Failed to load validation history.');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const _EmptyHint(text: 'No validations have been run yet.');
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = (docs[index].data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            return _GovVerificationCard(data: data);
          },
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PageTitle(
          title: 'Validation Reports',
          subtitle: 'Upload a site photo and run verification. Results are stored in Firestore.',
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: _isVerifying ? null : _runVerification,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isVerifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        _isVerifying ? 'Running...' : 'Run AI Verification',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: _border),
                  const SizedBox(height: 14),
                  Expanded(child: list),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageTitle(title: title, subtitle: subtitle),
        const SizedBox(height: 16),
        const _Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text('Coming soon.'),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectDropdown(BuildContext context) {
    final query = FirebaseService.instance.projectsCollection.where('status', isEqualTo: 'ongoing');
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final items = docs
            .map((d) {
              final data = (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
              final name = (data['name'] ?? '').toString();
              if (name.isEmpty) return null;
              return DropdownMenuItem<String>(
                value: d.id,
                child: Text(name, overflow: TextOverflow.ellipsis),
              );
            })
            .whereType<DropdownMenuItem<String>>()
            .toList();

        return DropdownButtonFormField<String>(
          value: items.any((e) => e.value == _selectedProjectId) ? _selectedProjectId : null,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            final doc = docs.firstWhere((e) => e.id == v, orElse: () => docs.first);
            final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            setState(() {
              _selectedProjectId = v;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: _cardBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _blue, width: 1.6),
            ),
          ),
          hint: const Text('-- Choose Active Project --'),
        );
      },
    );
  }

  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: text));
      _chatController.clear();
    });
  }

  Future<void> _pickDailyProgressImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _selectedImageBytes = Uint8List.fromList(bytes);
      _selectedImageName = file.name;
    });
  }

  Future<void> _analyzeDailyProgress() async {
    if (_selectedProjectId == null || _selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project and upload a photo first.')),
      );
      return;
    }

    try {
      setState(() => _isAnalyzing = true);
      final now = DateTime.now();
      final fileName = (_selectedImageName?.isNotEmpty ?? false) ? _selectedImageName! : 'site_photo.jpg';
      final storagePath = 'ai_verifications/${now.millisecondsSinceEpoch}_$fileName';
      final downloadUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        _selectedImageBytes!,
        contentType: _guessContentType(fileName),
      );

      final callable = FirebaseFunctions.instance.httpsCallable('verifyProgressImage');
      final res = await callable.call(<String, dynamic>{
        'imageUrl': downloadUrl,
        'storagePath': storagePath,
        'fileName': fileName,
        'projectId': _selectedProjectId,
        'projectName': _selectedProjectName,
      });

      final data = (res.data as Map?)?.cast<String, dynamic>();
      setState(() {
        _lastAnalysis = data ?? <String, dynamic>{};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analyze failed: $e')));
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _runVerification() async {
    try {
      setState(() => _isVerifying = true);
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) throw Exception('Selected file has no data.');

      final fileName = file.name.isNotEmpty ? file.name : 'site_photo.jpg';
      final now = DateTime.now();
      final storagePath = 'ai_verifications/${now.millisecondsSinceEpoch}_$fileName';

      final downloadUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        Uint8List.fromList(bytes),
        contentType: _guessContentType(fileName),
      );

      final callable = FirebaseFunctions.instance.httpsCallable('verifyProgressImage');
      await callable.call(<String, dynamic>{
        'imageUrl': downloadUrl,
        'storagePath': storagePath,
        'fileName': fileName,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification recorded.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification failed: $e')));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String? _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class _GovSidebar extends StatelessWidget {
  const _GovSidebar({required this.selected, required this.onSelect});
  final _AiNavItem selected;
  final ValueChanged<_AiNavItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_AiDashboardState._navBgTop, _AiDashboardState._navBgBottom],
        ),
        border: Border(right: BorderSide(color: _AiDashboardState._navBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _AiDashboardState._navActiveAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GovTrack AI',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'INFRA INTELLIGENCE',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _AiDashboardState._navMuted,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const _NavSectionTitle(text: 'MODULES'),
                    const SizedBox(height: 10),
                    _GovNavItem(
                      title: 'Command Center',
                      icon: Icons.dashboard_outlined,
                      active: selected == _AiNavItem.commandCenter,
                      onTap: () => onSelect(_AiNavItem.commandCenter),
                    ),
                    _GovNavItem(
                      title: 'Intelligence Chat',
                      icon: Icons.forum_outlined,
                      active: selected == _AiNavItem.intelligenceChat,
                      onTap: () => onSelect(_AiNavItem.intelligenceChat),
                    ),
                    _GovNavItem(
                      title: 'AI Daily Progress',
                      icon: Icons.document_scanner_outlined,
                      active: selected == _AiNavItem.aiDailyProgress,
                      onTap: () => onSelect(_AiNavItem.aiDailyProgress),
                    ),
                    const SizedBox(height: 18),
                    const _NavSectionTitle(text: 'MONITORING'),
                    const SizedBox(height: 10),
                    _GovNavItem(
                      title: 'Active Alerts',
                      icon: Icons.warning_amber_outlined,
                      showDot: true,
                      active: selected == _AiNavItem.activeAlerts,
                      onTap: () => onSelect(_AiNavItem.activeAlerts),
                    ),
                    _GovNavItem(
                      title: 'Validation Reports',
                      icon: Icons.fact_check_outlined,
                      active: selected == _AiNavItem.validationReports,
                      onTap: () => onSelect(_AiNavItem.validationReports),
                    ),
                    _GovNavItem(
                      title: 'Audit Logs',
                      icon: Icons.shield_outlined,
                      active: selected == _AiNavItem.auditLogs,
                      onTap: () => onSelect(_AiNavItem.auditLogs),
                    ),
                    const SizedBox(height: 18),
                    _GovNavItem(
                      title: 'System Settings',
                      icon: Icons.settings_outlined,
                      active: false,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: _AiDashboardState._navBorder),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _AiDashboardState._navActiveBg,
                  child: Text(
                    'JD',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AiDashboardState._navText,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Juan Dela Cruz',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Provincial Engineer',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.logout, color: _AiDashboardState._navMuted, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NavSectionTitle extends StatelessWidget {
  const _NavSectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: _AiDashboardState._navMuted,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
    );
  }
}

class _GovNavItem extends StatelessWidget {
  const _GovNavItem({
    required this.title,
    required this.icon,
    required this.active,
    required this.onTap,
    this.showDot = false,
  });

  final String title;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: active ? _AiDashboardState._navActiveBg : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: active ? Colors.white : _AiDashboardState._navText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active ? Colors.white : _AiDashboardState._navText,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (showDot)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({required this.tabIndex, required this.onTabChange});
  final int tabIndex;
  final ValueChanged<int> onTabChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _AiDashboardState._border)),
      ),
      child: Row(
        children: [
          Text(
            'AI Progress Validation Engine',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: _AiDashboardState._title,
                ),
          ),
          const Spacer(),
          _PillTabs(index: tabIndex, onChange: onTabChange),
        ],
      ),
    );
  }
}

class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.index, required this.onChange});
  final int index;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _AiDashboardState._border),
      ),
      child: Row(
        children: [
          _PillTab(text: 'Overview', active: index == 0, onTap: () => onChange(0)),
          _PillTab(text: 'Financials', active: index == 1, onTap: () => onChange(1)),
          _PillTab(text: 'Contractors', active: index == 2, onTap: () => onChange(2)),
        ],
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({required this.text, required this.active, required this.onTap});
  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: active ? _AiDashboardState._title : _AiDashboardState._subtitle,
              ),
        ),
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _AiDashboardState._border),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: _AiDashboardState._subtitle),
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: _AiDashboardState._title,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _AiDashboardState._subtitle),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _AiDashboardState._cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AiDashboardState._border),
        boxShadow: _AiDashboardState._shadow,
      ),
      child: child,
    );
  }
}

enum _MetricTone { normal, risk }

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.deltaText,
    required this.deltaUp,
    this.tone = _MetricTone.normal,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final String deltaText;
  final bool deltaUp;
  final _MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final risk = tone == _MetricTone.risk;
    final bg = risk ? const Color(0xFFFFF1F2) : Colors.white;
    final border = risk ? const Color(0xFFFCA5A5) : _AiDashboardState._border;
    final deltaColor = deltaUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: _AiDashboardState._shadow,
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _AiDashboardState._subtitle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: _AiDashboardState._subtitle,
                              letterSpacing: 0.6,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _AiDashboardState._border),
                      ),
                      child: Row(
                        children: [
                          Icon(deltaUp ? Icons.trending_up : Icons.trending_down, size: 14, color: deltaColor),
                          const SizedBox(width: 6),
                          Text(
                            deltaText,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: deltaColor,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _AiDashboardState._title,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._subtitle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadDropzone extends StatelessWidget {
  const _UploadDropzone({required this.bytes, required this.onPick});
  final Uint8List? bytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 340,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AiDashboardState._blue, width: 1.2),
        ),
        child: bytes == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.photo_camera_outlined, color: _AiDashboardState._blue, size: 26),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Upload Site Photo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._title,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Drag & drop or click to browse',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._subtitle),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'JPG, PNG • Max 10MB • Geo-tag preferred',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                    ),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(bytes!, fit: BoxFit.cover),
              ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _AiDashboardState._subtitle)),
    );
  }
}

class _GovVerificationCard extends StatelessWidget {
  const _GovVerificationCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final createdAt = data['createdAt'];
    DateTime? created;
    if (createdAt is Timestamp) created = createdAt.toDate();
    final createdText = created == null
        ? 'Unknown time'
        : '${created.year}-${created.month.toString().padLeft(2, '0')}-${created.day.toString().padLeft(2, '0')} '
            '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    final pass = (data['pass'] ?? false) == true;
    final confidence = ((data['confidence'] ?? 0.0) as num).toDouble().clamp(0.0, 1.0);
    final statusText = pass ? 'PASS' : 'FAIL';
    final statusColor = pass ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AiDashboardState._border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: pass ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(pass ? Icons.check_circle : Icons.cancel, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verification: $statusText',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _AiDashboardState._title,
                      ),
                ),
                const SizedBox(height: 2),
                Text(createdText, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._subtitle)),
              ],
            ),
          ),
          Text(
            '${(confidence * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: _AiDashboardState._title,
                ),
          ),
        ],
      ),
    );
  }
}

class _GovTrackReportCard extends StatelessWidget {
  const _GovTrackReportCard({required this.projectName, required this.analysis});
  final String projectName;
  final Map<String, dynamic> analysis;

  @override
  Widget build(BuildContext context) {
    final confidence = ((analysis['confidence'] ?? 0.0) as num).toDouble().clamp(0.0, 1.0);
    final confPct = (confidence * 100).round();
    final pass = (analysis['pass'] ?? false) == true;
    final date = DateTime.now();
    final dateText = '${_monthName(date.month)} ${date.day}, ${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final stages = _inferStages(analysis);
    final scheduleDelta = pass ? '+1%' : '-2%';
    final scheduleOk = pass;
    final estCompletion = (confidence * 40).clamp(0, 100).round();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AiDashboardState._border),
        boxShadow: _AiDashboardState._shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF0B1220),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.description_outlined, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GOVTRACK AI REPORT',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        projectName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
                Text(dateText, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MiniStatCard(
                        title: 'ESTIMATED COMPLETION',
                        value: '$estCompletion% ',
                        subValue: '/ 35% Planned',
                        barValue: estCompletion / 100.0,
                        barColor: _AiDashboardState._blue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _MiniStatCard(
                        title: 'SCHEDULE VARIANCE',
                        value: scheduleDelta,
                        subValue: scheduleOk ? 'On Schedule' : 'Behind Schedule',
                        valueColor: scheduleOk ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'VISIBLE CONSTRUCTION STAGE',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _AiDashboardState._title,
                        letterSpacing: 0.4,
                      ),
                ),
                const SizedBox(height: 10),
                Container(height: 1, color: _AiDashboardState._border),
                const SizedBox(height: 12),
                for (final s in stages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(child: Text(s.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _AiDashboardState._title))),
                        Row(
                          children: [
                            if (s.isComplete)
                              const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              s.statusText,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: s.statusColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _AiDashboardState._border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Structural Confidence Score',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: _AiDashboardState._title,
                              ),
                        ),
                      ),
                      Text(
                        '$confPct%',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: pass ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.title,
    required this.value,
    this.subValue = '',
    this.valueColor,
    this.barValue,
    this.barColor,
  });

  final String title;
  final String value;
  final String subValue;
  final Color? valueColor;
  final double? barValue;
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AiDashboardState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._subtitle, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: valueColor ?? _AiDashboardState._title,
                    ),
              ),
              if (subValue.isNotEmpty) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(subValue, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._subtitle)),
                ),
              ],
            ],
          ),
          if (barValue != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: barValue!.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(barColor ?? _AiDashboardState._blue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _AiDashboardState._border),
          boxShadow: _AiDashboardState._shadow,
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file, size: 18, color: _AiDashboardState._subtitle),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Ask GovTrack AI about projects, budgets, or milestones...',
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, color: _AiDashboardState._blue),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.isUser, required this.text});
  final bool isUser;
  final String text;
}

class _GovChatBubble extends StatelessWidget {
  const _GovChatBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubbleColor = isUser ? _AiDashboardState._blue : Colors.white;
    final textColor = isUser ? Colors.white : _AiDashboardState._title;
    final border = isUser ? Colors.transparent : _AiDashboardState._border;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isUser) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.smart_toy_outlined, color: _AiDashboardState._blue, size: 18),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Text(
              message.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor, height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}

class _StageItem {
  const _StageItem(this.name, this.statusText, this.statusColor, this.isComplete);
  final String name;
  final String statusText;
  final Color statusColor;
  final bool isComplete;
}

List<_StageItem> _inferStages(Map<String, dynamic> analysis) {
  final labels = (analysis['labels'] is List)
      ? (analysis['labels'] as List).map((e) => e.toString().toLowerCase()).toList()
      : <String>[];
  final hasFoundation = labels.any((e) => e.contains('concrete') || e.contains('foundation'));
  final hasRoof = labels.any((e) => e.contains('roof'));
  final hasWall = labels.any((e) => e.contains('wall') || e.contains('brick'));
  final hasColumn = labels.any((e) => e.contains('column') || e.contains('beam'));

  return [
    _StageItem('Foundation', hasFoundation ? 'Completed' : 'Not started', hasFoundation ? const Color(0xFF16A34A) : _AiDashboardState._subtitle, hasFoundation),
    _StageItem('Structural Columns', hasColumn ? 'Completed' : 'Not started', hasColumn ? const Color(0xFF16A34A) : _AiDashboardState._subtitle, hasColumn),
    _StageItem('Roofing', hasRoof ? '10% complete' : 'Not started', _AiDashboardState._subtitle, false),
    _StageItem('Walls', hasWall ? 'In progress' : 'Not started', _AiDashboardState._subtitle, false),
  ];
}

String _monthName(int m) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return (m >= 1 && m <= 12) ? names[m - 1] : 'Month';
}
