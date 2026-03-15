import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../models/daily_report_model.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/govtrack_ai_service.dart';
import '../../widgets/common/status_chip.dart';
import 'widgets/admin_bottom_nav.dart';

class AdminReports extends StatelessWidget {
  const AdminReports({
    super.key,
    this.showBottomNav = true,
    this.dashboardRoute = RouteNames.adminDashboard,
  });

  final bool showBottomNav;
  final String dashboardRoute;

  @override
  Widget build(BuildContext context) {
    return _AiDashboard(
      onOpenDailyReport: (report) => _showReportDetailsDialog(context, report),
      showBottomNav: showBottomNav,
      dashboardRoute: dashboardRoute,
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
  intelligenceChat,
  imageGenerate,
}

class _AiDashboard extends StatefulWidget {
  const _AiDashboard({
    required this.onOpenDailyReport,
    required this.showBottomNav,
    required this.dashboardRoute,
  });

  final ValueChanged<DailyReportModel> onOpenDailyReport;
  final bool showBottomNav;
  final String dashboardRoute;

  @override
  State<_AiDashboard> createState() => _AiDashboardState();
}

class _AiDashboardState extends State<_AiDashboard> {
  static const Color _navBorder = Color(0xFFE2E8F0);
  static const Color _navMuted = Color(0xFF64748B);
  static const Color _navActiveBg = Color(0xFFF1F5F9);
  static const Color _navActiveAccent = Color(0xFF2563EB);

  static const Color _pageBg = Color(0xFFF3F4F6);
  static const Color _cardBg = Color(0xFFFFFFFF);
  static const Color _border = Color(0xFFE5E7EB);
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

  Uint8List? _chatImageBytes;
  String? _chatImageName;

  _AiNavItem _selected = _AiNavItem.intelligenceChat;
  int _topTabIndex = 0;

  bool _isAnalyzing = false;
  bool _isGeneratingReport = false;

  String? _selectedProjectId;
  String? _selectedProjectName;

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;

  String? _lastAnalyzedImageUrl;
  String? _lastAnalyzedStoragePath;
  String? _lastAnalyzedFileName;
  double? _lastAnalyzedProgressPercent;

  double? _lastPhotoLat;
  double? _lastPhotoLng;
  String? _lastPhotoAddress;
  DateTime? _lastPhotoCapturedAt;

  Map<String, dynamic>? _lastAnalysis;

  final GovTrackAiService _govTrackAiService = GovTrackAiService();

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to use GovTrack AI.')),
        );
        context.go(RouteNames.login);
      }
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _pickChatImage() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Upload from Gallery'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (picked == null) return;
                  final bytes = await picked.readAsBytes();
                  if (!mounted) return;
                  setState(() {
                    _chatImageBytes = bytes;
                    _chatImageName = picked.name;
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take Photo'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                  if (picked == null) return;
                  final bytes = await picked.readAsBytes();
                  if (!mounted) return;
                  setState(() {
                    _chatImageBytes = bytes;
                    _chatImageName = picked.name;
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 980;
    return Scaffold(
      backgroundColor: _pageBg,
      drawer: isNarrow
          ? Drawer(
              child: SafeArea(
                child: _GovSidebar(
                  selected: _selected,
                  onSelect: (v) {
                    Navigator.of(context).pop();
                    setState(() {
                      _selected = v;
                      _topTabIndex = v == _AiNavItem.intelligenceChat ? 0 : 1;
                    });
                  },
                ),
              ),
            )
          : null,
      body: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopHeader(
                  tabIndex: _topTabIndex,
                  onTabChange: (i) => setState(() {
                    _topTabIndex = i;
                    _selected = i == 0 ? _AiNavItem.intelligenceChat : _AiNavItem.imageGenerate;
                  }),
                  showMenu: true,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildBody(context),
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GovSidebar(
                  selected: _selected,
                  onSelect: (v) => setState(() {
                    _selected = v;
                    _topTabIndex = v == _AiNavItem.intelligenceChat ? 0 : 1;
                  }),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TopHeader(
                        tabIndex: _topTabIndex,
                        onTabChange: (i) => setState(() {
                          _topTabIndex = i;
                          _selected = i == 0 ? _AiNavItem.intelligenceChat : _AiNavItem.imageGenerate;
                        }),
                        showMenu: false,
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
      bottomNavigationBar: widget.showBottomNav
          ? const AdminBottomNavBar(current: AdminNavItem.dashboard)
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_selected) {
      case _AiNavItem.intelligenceChat:
        return _buildChat(context);
      case _AiNavItem.imageGenerate:
        return _buildAiDailyProgress(context);
    }
  }

  Future<bool> _ensureFunctionsAuthenticated() async {
    // Preflight: if DNS cannot resolve Firebase hosts, callable auth will often fail
    // and surface as UNAUTHENTICATED. Detect this early and show a clearer message.
    try {
      final res = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 4));
      if (res.isEmpty) {
        throw const SocketException('DNS lookup returned no results');
      }
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No internet/DNS access to Firebase. Please change network or Private DNS, then try again.',
          ),
        ),
      );
      return false;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again. Your session expired.')),
      );
      return false;
    }

    try {
      await user.getIdToken(true);
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot refresh session. Please check your internet/DNS and try again.',
          ),
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _generateGovTrackReport() async {
    final projectId = _selectedProjectId;
    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project first.')),
      );
      return;
    }

    final okAuth = await _ensureFunctionsAuthenticated();
    if (!okAuth) return;

    try {
      setState(() => _isGeneratingReport = true);

      final projectDoc = await FirebaseService.instance.projectsCollection.doc(projectId).get();
      final projectData = (projectDoc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final projectName = _selectedProjectName ?? (projectData['name'] ?? 'Selected Project').toString();

      final recentDailyReportsQuery = await FirebaseService.instance
          .dailyReportsCollection(projectId)
          .orderBy('reportDate', descending: true)
          .limit(5)
          .get();

      final recentDailyReports = recentDailyReportsQuery.docs
          .map((d) => ((d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{}))
          .toList();

      final progressPercent = _calculateProgressPercent(recentDailyReports);

      final assignedSiteManagerId = (projectData['siteManagerId'] ?? '').toString().trim();
      final assignedSiteManagerName = (projectData['siteManagerName'] ?? '').toString().trim();
      final assignedSiteManagerEmail = assignedSiteManagerId.isEmpty
          ? ''
          : await _tryGetUserEmail(assignedSiteManagerId);

      Map<String, dynamic> analysis;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('generateGovTrackReportGemini');
        final res = await callable
            .call(<String, dynamic>{
          'projectId': projectId,
          'projectName': projectName,
          'projectData': projectData,
          'recentDailyReports': recentDailyReports,
        })
            .timeout(const Duration(seconds: 60));

        final data = (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        analysis = (data['analysis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        if (analysis.isEmpty) {
          throw Exception('Gemini returned empty analysis.');
        }
      } catch (_) {
        analysis = await _govTrackAiService.generateGovTrackReport(
          projectId: projectId,
          projectName: projectName,
          projectData: projectData,
          recentDailyReports: recentDailyReports,
        );
      }

      await FirebaseService.instance.projectsCollection.doc(projectId).collection('govtrack_reports').add(
        <String, dynamic>{
          'projectId': projectId,
          'projectName': projectName,
          'progressPercent': progressPercent,
          'analysis': analysis,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      final currentUser = AuthService.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_progress_report',
          'projectId': projectId,
          'projectName': projectName,
          'progressPercent': progressPercent,
          'assignedSiteManagerId': assignedSiteManagerId,
          'assignedSiteManagerName': assignedSiteManagerName,
          'assignedSiteManagerEmail': assignedSiteManagerEmail,
          'submittedById': currentUser?.id,
          'submittedByName': '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim(),
          'submittedByEmail': currentUser?.email,
          'analysis': analysis,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      setState(() {
        _lastAnalysis = analysis;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GovTrack report generated and saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generate report failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingReport = false);
    }
  }

  double _calculateProgressPercent(List<Map<String, dynamic>> reports) {
    var total = 0.0;
    var count = 0;
    for (final r in reports) {
      final accomplishments = (r['workAccomplishments'] as List?)?.cast<dynamic>() ?? const [];
      for (final raw in accomplishments) {
        final item = (raw as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final pct = item['percentageComplete'];
        if (pct is num) {
          total += pct.toDouble();
          count += 1;
        }
      }
    }
    if (count == 0) return 0;
    final avg = total / count;
    if (avg.isNaN) return 0;
    return avg.clamp(0, 100);
  }

  Future<String> _tryGetUserEmail(String userId) async {
    try {
      final doc = await FirebaseService.instance.usersCollection.doc(userId).get();
      final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      return (data['email'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Widget _buildChat(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showFooter = constraints.maxHeight >= 720;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                      onPickImage: _pickChatImage,
                      attachmentBytes: _chatImageBytes,
                      attachmentName: _chatImageName,
                      onRemoveImage: () {
                        setState(() {
                          _chatImageBytes = null;
                          _chatImageName = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (showFooter) ...[
              const SizedBox(height: 10),
              Text(
                'GovTrack AI uses simulated structural confidence scores. Always verify critical alerts on-site.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _subtitle),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAiDailyProgress(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: bottomInset + 24),
      children: [
        const SizedBox(height: 6),
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
                if (_selectedProjectId != null) ...[
                  const SizedBox(height: 12),
                  _AssignedProjectInfo(projectId: _selectedProjectId!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'GOVTRACK REPORT',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _subtitle,
                      ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _isGeneratingReport ? null : _generateGovTrackReport,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isGeneratingReport
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      _isGeneratingReport ? 'Generating...' : 'Generate GovTrack Report (Free / Local)',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Runs on this PC via Ollama (127.0.0.1:11434). Generated reports are saved to Firestore.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _subtitle),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UploadDropzone(
                  bytes: _selectedImageBytes,
                  onPick: _pickDailyProgressImage,
                  stampText: _buildGpsStampText(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _isAnalyzing ? null : _pickDailyProgressImage,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Upload Photo', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    onPressed: _isAnalyzing ? null : _analyzeDailyProgress,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Analyze Image', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _canSubmitProgressToAdmin() ? _submitProgressToAdmin : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Submit to Admin', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                if (_lastAnalyzedProgressPercent != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.insights_outlined, size: 18, color: _AiDashboardState._subtitle),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Progress: ${_lastAnalyzedProgressPercent!.toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: _title,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_selectedProjectId != null) ...[
          const SizedBox(height: 18),
          _buildLatestGovTrackReport(context),
        ] else if (_lastAnalysis != null) ...[
          const SizedBox(height: 18),
          _GovTrackReportCard(
            projectName: _selectedProjectName ?? 'Selected Project',
            analysis: _lastAnalysis!,
          ),
        ],
      ],
    );
  }

  Widget _buildLatestGovTrackReport(BuildContext context) {
    final projectId = _selectedProjectId;
    if (projectId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.projectsCollection
          .doc(projectId)
          .collection('govtrack_reports')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_lastAnalysis == null) {
            return const SizedBox.shrink();
          }
          return _GovTrackReportCard(
            projectName: _selectedProjectName ?? 'Selected Project',
            analysis: _lastAnalysis!,
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          if (_lastAnalysis == null) {
            return const _EmptyHint(text: 'No GovTrack reports generated yet.');
          }
          return _GovTrackReportCard(
            projectName: _selectedProjectName ?? 'Selected Project',
            analysis: _lastAnalysis!,
          );
        }

        final data = (docs.first.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final analysis = (data['analysis'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        return _GovTrackReportCard(
          projectName: _selectedProjectName ?? 'Selected Project',
          analysis: analysis,
        );
      },
    );
  }

  Widget _buildProjectDropdown(BuildContext context) {
    final user = AuthService.instance.currentUser;
    var query = FirebaseService.instance.projectsCollection.where('status', isEqualTo: 'ongoing');
    if (user != null && user.isSiteManager) {
      query = query.where('siteManagerId', isEqualTo: user.id);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 56, child: Center(child: CircularProgressIndicator()));
        }

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

        if (_selectedProjectId == null && docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_selectedProjectId != null) return;
            final first = docs.first;
            final data = (first.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
            setState(() {
              _selectedProjectId = first.id;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          });
        }

        return DropdownButtonFormField<String>(
          initialValue: items.any((e) => e.value == _selectedProjectId) ? _selectedProjectId : null,
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

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    debugPrint('govtrack: _sendChat start');

    final okAuth = await _ensureFunctionsAuthenticated();
    if (!okAuth) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(isUser: true, text: text));
        _messages.add(const _ChatMessage(
          isUser: false,
          text: 'Please sign in again, then try sending your message.',
        ));
        _chatController.clear();
      });
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: text));
      _messages.add(const _ChatMessage(isUser: false, text: 'Thinking…'));
      _chatController.clear();
    });

    try {
      Map<String, dynamic> data;

      String? attachmentUrl;
      String? attachmentStoragePath;
      String? attachmentFileName;

      if (_chatImageBytes != null) {
        final now = DateTime.now();
        final fileName = (_chatImageName?.isNotEmpty ?? false) ? _chatImageName! : 'chat_image.jpg';
        final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final storagePath = 'govtrack_chat_attachments/${now.millisecondsSinceEpoch}_$safeFileName';
        final downloadUrl = await FirebaseService.instance.uploadFile(
          storagePath,
          _chatImageBytes!,
          contentType: _guessContentType(fileName),
        );
        attachmentUrl = downloadUrl;
        attachmentStoragePath = storagePath;
        attachmentFileName = fileName;
      }

      Future<String?> getToken({required bool forceRefresh}) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return null;
        try {
          return await user.getIdToken(forceRefresh);
        } catch (_) {
          return null;
        }
      }

      Future<String?> getBestToken() async {
        final t1 = await getToken(forceRefresh: false);
        if (t1 != null && t1.trim().isNotEmpty) return t1;
        final t2 = await getToken(forceRefresh: true);
        if (t2 != null && t2.trim().isNotEmpty) return t2;
        return null;
      }

      Future<Map<String, dynamic>> callGemini() async {
        final idToken = await getBestToken();
        if (idToken == null || idToken.trim().isEmpty) {
          debugPrint('govtrack: missing idToken before calling govtrackChatGemini');
          developer.log(
            'GovTrack chat: missing idToken before calling govtrackChatGemini',
            name: 'govtrack',
          );
          throw Exception(
            'Cannot get a session token. Please check your internet/DNS and try again.',
          );
        }
        final user = FirebaseAuth.instance.currentUser;
        debugPrint(
          'govtrack: calling govtrackChatGemini uid=${user?.uid ?? 'null'} tokenLen=${idToken.length}',
        );
        developer.log(
          'Calling govtrackChatGemini',
          name: 'govtrack',
          error: {
            'uid': user?.uid,
            'tokenLen': idToken.length,
          },
        );
        final callable = FirebaseFunctions.instance.httpsCallable('govtrackChatGemini');
        final res = await callable
            .call(<String, dynamic>{
          'message': text,
          'idToken': idToken,
          'imageUrl': attachmentUrl,
          'storagePath': attachmentStoragePath,
          'fileName': attachmentFileName,
        })
            .timeout(const Duration(seconds: 45));
        debugPrint('govtrack: govtrackChatGemini returned');
        return (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      }

      try {
        data = await callGemini();
      } on FirebaseFunctionsException catch (e, st) {
        debugPrint(
          'govtrack: FirebaseFunctionsException code=${e.code} message=${e.message} details=${e.details}',
        );
        developer.log(
          'govtrackChatGemini FirebaseFunctionsException',
          name: 'govtrack',
          error: {
            'code': e.code,
            'message': e.message,
            'details': e.details,
          },
          stackTrace: st,
        );
        if (e.code == 'unauthenticated') {
          await getToken(forceRefresh: true);
          data = await callGemini();
        } else {
          rethrow;
        }
      } catch (e, st) {
        debugPrint('govtrack: non-FirebaseFunctionsException error=$e');
        developer.log(
          'govtrackChatGemini failed (non-FirebaseFunctionsException)',
          name: 'govtrack',
          error: e,
          stackTrace: st,
        );
        rethrow;
      }

      final reply = (data['reply'] ?? '').toString().trim();

      final currentUser = AuthService.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_chat',
          'message': text,
          'reply': reply,
          'imageUrl': attachmentUrl,
          'storagePath': attachmentStoragePath,
          'fileName': attachmentFileName,
          'projectId': _selectedProjectId,
          'projectName': _selectedProjectName,
          'submittedById': currentUser?.id,
          'submittedByName': '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim(),
          'submittedByEmail': currentUser?.email,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      if (mounted) {
        setState(() {
          _chatImageBytes = null;
          _chatImageName = null;
        });
      }

      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isUser == false && _messages.last.text == 'Thinking…') {
          _messages.removeLast();
        }
        _messages.add(_ChatMessage(
          isUser: false,
          text: reply.isEmpty ? 'No response received. Please try again.' : reply,
        ));
      });
    } catch (e) {
      final u = FirebaseAuth.instance.currentUser;
      final uid = u?.uid;
      final msg = e is FirebaseFunctionsException
          ? 'Chat failed (${e.code}): message=${e.message ?? 'null'} details=${e.details ?? 'null'} (uid: ${uid ?? 'null'})'
          : 'Chat failed: $e (uid: ${uid ?? 'null'})';
      debugPrint('govtrack: $msg');
      developer.log(
        'GovTrack chat failed',
        name: 'govtrack',
        error: msg,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.isUser == false &&
            _messages.last.text == 'Thinking…') {
          _messages.removeLast();
        }
        _messages.add(_ChatMessage(isUser: false, text: msg));
      });
    }
  }

  Future<void> _pickDailyProgressImage() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Upload from Gallery'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickDailyProgressImageFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take Photo (Camera)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _pickDailyProgressImageFromCamera();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDailyProgressImageFromGallery() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final picker = ImagePicker();
        final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
        if (file == null) return;
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _selectedImageBytes = Uint8List.fromList(bytes);
          _selectedImageName = file.name;
          _lastAnalyzedProgressPercent = null;
          _lastAnalyzedImageUrl = null;
          _lastAnalyzedStoragePath = null;
          _lastAnalyzedFileName = null;
          _lastPhotoLat = null;
          _lastPhotoLng = null;
          _lastPhotoAddress = null;
          _lastPhotoCapturedAt = null;
        });
        return;
      }

      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = Uint8List.fromList(bytes);
        _selectedImageName = picked.name;
        _lastAnalyzedProgressPercent = null;
        _lastAnalyzedImageUrl = null;
        _lastAnalyzedStoragePath = null;
        _lastAnalyzedFileName = null;
        _lastPhotoLat = null;
        _lastPhotoLng = null;
        _lastPhotoAddress = null;
        _lastPhotoCapturedAt = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery upload failed: $e')),
      );
    }
  }

  String? _buildGpsStampText() {
    if (_lastPhotoLat == null || _lastPhotoLng == null || _lastPhotoCapturedAt == null) {
      return null;
    }

    final d = _lastPhotoCapturedAt!;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final dt = '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year} '
        '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';

    final addr = (_lastPhotoAddress ?? '').trim();
    final lat = _lastPhotoLat!.toStringAsFixed(6);
    final lng = _lastPhotoLng!.toStringAsFixed(6);
    return '${addr.isEmpty ? 'Location captured' : addr}\nLat $lat  Lng $lng\n$dt';
  }

  Future<void> _captureAndSetGpsStamp() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Location services to tag this photo.')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied. Photo will not be GPS-tagged.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String? address;
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').trim().isNotEmpty) (p.street ?? '').trim(),
            if ((p.locality ?? '').trim().isNotEmpty) (p.locality ?? '').trim(),
            if ((p.administrativeArea ?? '').trim().isNotEmpty) (p.administrativeArea ?? '').trim(),
            if ((p.country ?? '').trim().isNotEmpty) (p.country ?? '').trim(),
          ];
          address = parts.join(', ');
        }
      } catch (_) {
        address = null;
      }

      if (!mounted) return;
      setState(() {
        _lastPhotoLat = pos.latitude;
        _lastPhotoLng = pos.longitude;
        _lastPhotoAddress = address;
        _lastPhotoCapturedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get GPS location: $e')),
      );
    }
  }

  Future<void> _pickDailyProgressImageFromCamera() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final picker = ImagePicker();
        final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 92);
        if (file == null) return;
        await _captureAndSetGpsStamp();
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _selectedImageBytes = Uint8List.fromList(bytes);
          _selectedImageName = file.name;
          _lastAnalyzedProgressPercent = null;
          _lastAnalyzedImageUrl = null;
          _lastAnalyzedStoragePath = null;
          _lastAnalyzedFileName = null;
        });
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera upload is supported on mobile devices only.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera upload failed: $e')),
      );
    }
  }

  double? _extractProgressPercentFromAnalysis(Map<String, dynamic>? analysis) {
    if (analysis == null) return null;

    final direct = analysis['progressPercent'] ?? analysis['progress_percent'] ?? analysis['progress'];
    if (direct is num) {
      return direct.toDouble().clamp(0, 100);
    }

    final schedule = (analysis['schedule'] as Map?)?.cast<String, dynamic>();
    final schedulePct = schedule?['progressPercent'] ?? schedule?['progress'];
    if (schedulePct is num) {
      return schedulePct.toDouble().clamp(0, 100);
    }

    final confidence = analysis['confidence'];
    if (confidence is num) {
      return (confidence.toDouble().clamp(0.0, 1.0) * 100).clamp(0, 100);
    }
    return null;
  }

  bool _canSubmitProgressToAdmin() {
    return _selectedProjectId != null &&
        _lastAnalysis != null &&
        _lastAnalyzedProgressPercent != null &&
        (_lastAnalyzedImageUrl?.isNotEmpty ?? false);
  }

  Future<void> _submitProgressToAdmin() async {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    if (_lastAnalysis == null) return;
    if (_lastAnalyzedProgressPercent == null) return;

    try {
      final projectDoc = await FirebaseService.instance.projectsCollection.doc(projectId).get();
      final projectData = (projectDoc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final projectName = _selectedProjectName ?? (projectData['name'] ?? 'Selected Project').toString();

      final assignedSiteManagerId = (projectData['siteManagerId'] ?? '').toString().trim();
      final assignedSiteManagerName = (projectData['siteManagerName'] ?? '').toString().trim();
      final assignedSiteManagerEmail = assignedSiteManagerId.isEmpty
          ? ''
          : await _tryGetUserEmail(assignedSiteManagerId);

      final currentUser = AuthService.instance.currentUser;

      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_progress_report',
          'projectId': projectId,
          'projectName': projectName,
          'progressPercent': _lastAnalyzedProgressPercent,
          'assignedSiteManagerId': assignedSiteManagerId,
          'assignedSiteManagerName': assignedSiteManagerName,
          'assignedSiteManagerEmail': assignedSiteManagerEmail,
          'imageUrl': _lastAnalyzedImageUrl,
          'storagePath': _lastAnalyzedStoragePath,
          'fileName': _lastAnalyzedFileName,
          'photoLat': _lastPhotoLat,
          'photoLng': _lastPhotoLng,
          'photoAddress': _lastPhotoAddress,
          'photoCapturedAt': _lastPhotoCapturedAt == null ? null : Timestamp.fromDate(_lastPhotoCapturedAt!),
          'analysis': _lastAnalysis,
          'submittedById': currentUser?.id,
          'submittedByName': '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim(),
          'submittedByEmail': currentUser?.email,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted to Admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
    }
  }

  Future<void> _analyzeDailyProgress() async {
    if (_selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project first.')),
      );
      return;
    }
    if (_selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload a site photo first.')),
      );
      return;
    }

    try {
      setState(() => _isAnalyzing = true);

      final fbUser = AuthService.instance.currentFirebaseUser;
      if (fbUser == null) {
        throw FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'No Firebase user is signed in.',
        );
      }

      final idToken = await fbUser.getIdToken(true);
      final now = DateTime.now();
      final fileName = (_selectedImageName?.isNotEmpty ?? false) ? _selectedImageName! : 'site_photo.jpg';
      final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final storagePath = 'ai_verifications/${now.millisecondsSinceEpoch}_$safeFileName';
      final downloadUrl = await FirebaseService.instance.uploadFile(
        storagePath,
        _selectedImageBytes!,
        contentType: _guessContentType(fileName),
      );

      final callable = FirebaseFunctions.instance.httpsCallable('verifyProgressImage');
      final res = await callable
          .call(<String, dynamic>{
        'imageUrl': downloadUrl,
        'storagePath': storagePath,
        'fileName': fileName,
        'projectId': _selectedProjectId,
        'projectName': _selectedProjectName,
        'idToken': idToken,
      })
          .timeout(const Duration(seconds: 90));

      final data = (res.data as Map?)?.cast<String, dynamic>();
      setState(() {
        _lastAnalysis = data ?? <String, dynamic>{};
        _lastAnalyzedImageUrl = downloadUrl;
        _lastAnalyzedStoragePath = storagePath;
        _lastAnalyzedFileName = fileName;
        _lastAnalyzedProgressPercent = _extractProgressPercentFromAnalysis(data);
      });

      final currentUser = AuthService.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_image_analysis',
          'projectId': _selectedProjectId,
          'projectName': _selectedProjectName,
          'imageUrl': downloadUrl,
          'fileName': fileName,
          'storagePath': storagePath,
          'analysis': data,
          'submittedById': currentUser?.id,
          'submittedByName': '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim(),
          'submittedByEmail': currentUser?.email,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (e) {
      final msg = e is FirebaseFunctionsException
          ? 'Analyze failed (${e.code}): ${e.message ?? e.details ?? 'Unknown error'}'
          : 'Analyze failed: $e';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
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
  const _GovSidebar({
    required this.selected,
    required this.onSelect,
  });
  final _AiNavItem selected;
  final ValueChanged<_AiNavItem> onSelect;

  String _formatDateTime(dynamic createdAt) {
    DateTime? d;
    if (createdAt is Timestamp) d = createdAt.toDate();
    if (createdAt is DateTime) d = createdAt;
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.month}/${d.day}/${d.year}  ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'govtrack_chat':
        return 'AI Chat';
      case 'govtrack_image_analysis':
        return 'AI Image';
      case 'govtrack_progress_report':
        return 'GovTrack Report';
      default:
        return 'AI Activity';
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'govtrack_chat':
        return Icons.forum_outlined;
      case 'govtrack_image_analysis':
        return Icons.image_outlined;
      case 'govtrack_progress_report':
        return Icons.auto_awesome_outlined;
      default:
        return Icons.history;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;
    final displayName = '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim();
    final email = (currentUser?.email ?? '').trim();
    final initialsSource = displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : 'User');
    final parts = initialsSource.split(RegExp(r'\s+|\.|\-|\_')).where((e) => e.trim().isNotEmpty).toList();
    final initials = parts.isEmpty
        ? 'U'
        : (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();

    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _AiDashboardState._navBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
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
                _PageTitle(
                  title: 'GovTrack AI',
                  subtitle: 'INFRA INTELLIGENCE',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const _NavSectionTitle(text: 'HISTORY'),
                    const SizedBox(height: 10),
                    if (currentUser == null)
                      Text(
                        'Login required to view history.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                      )
                    else
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseService.instance.aiAnalysisCollection
                            .where('submittedById', isEqualTo: currentUser.id)
                            .orderBy('createdAt', descending: true)
                            .limit(30)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final docs = snapshot.data?.docs ?? const [];
                          final filtered = docs.where((d) {
                            final data = (d.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                            final kind = (data['kind'] ?? '').toString();
                            return kind == 'govtrack_chat' || kind == 'govtrack_image_analysis' || kind == 'govtrack_progress_report';
                          }).toList();

                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Loading history…',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                              ),
                            );
                          }

                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No AI history yet.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              for (final doc in filtered) ...[
                                Builder(
                                  builder: (context) {
                                    final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                                    final kind = (data['kind'] ?? '').toString();
                                    final title = _kindLabel(kind);
                                    final projectName = (data['projectName'] ?? '').toString().trim();
                                    final when = _formatDateTime(data['createdAt']);
                                    final message = (data['message'] ?? '').toString().trim();

                                    final subtitleParts = <String>[
                                      if (projectName.isNotEmpty) projectName,
                                      if (when.isNotEmpty) when,
                                      if (kind == 'govtrack_chat' && message.isNotEmpty) message,
                                    ];

                                    final subtitle = subtitleParts.join(' • ');

                                    return _GovNavItem(
                                      title: title,
                                      icon: _kindIcon(kind),
                                      active: false,
                                      onTap: () {
                                        if (kind == 'govtrack_chat') {
                                          onSelect(_AiNavItem.intelligenceChat);
                                        } else {
                                          onSelect(_AiNavItem.imageGenerate);
                                        }
                                      },
                                      subtitle: subtitle.isEmpty ? null : subtitle,
                                    );
                                  },
                                ),
                              ],
                            ],
                          );
                        },
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
                  backgroundColor: Colors.black.withValues(alpha: 0.04),
                  child: Text(
                    initials,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AiDashboardState._title,
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
                        displayName.isEmpty ? 'Site Manager' : displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AiDashboardState._title,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.isEmpty ? '—' : email,
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
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

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
                  color: active ? _AiDashboardState._navActiveAccent : Colors.black.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: active ? _AiDashboardState._title : Colors.black.withValues(alpha: 0.78),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _AiDashboardState._navMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
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
  const _TopHeader({
    required this.tabIndex,
    required this.onTabChange,
    required this.showMenu,
  });
  final int tabIndex;
  final ValueChanged<int> onTabChange;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 720;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _AiDashboardState._border)),
      ),
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: showMenu ? (isNarrow ? 86 : 84) : (isNarrow ? 58 : 62),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: showMenu
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Builder(
                            builder: (context) => IconButton(
                              icon: const Icon(Icons.menu),
                              onPressed: () => Scaffold.of(context).openDrawer(),
                              tooltip: 'Menu',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'GovTrack AI',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: isNarrow ? 150 : 220,
                            height: 40,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                filled: true,
                                fillColor: const Color(0xFFF1F5F9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _PillTabs(index: tabIndex, onChange: onTabChange),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 4,
                          children: [
                            Text(
                              'GovTrack AI',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: isNarrow ? 160 : 220,
                                  height: 40,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search',
                                      prefixIcon: const Icon(Icons.search, size: 20),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                      filled: true,
                                      fillColor: const Color(0xFFF1F5F9),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _PillTabs(index: tabIndex, onChange: onTabChange),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
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
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _AiDashboardState._border),
          ),
        ),
        child: Row(
          children: [
            _PillTab(text: 'Intelligence Chat', active: index == 0, onTap: () => onChange(0)),
            _PillTab(text: 'AI Daily Progress', active: index == 1, onTap: () => onChange(1)),
          ],
        ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? _AiDashboardState._navActiveAccent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: active ? _AiDashboardState._navActiveAccent : _AiDashboardState._subtitle,
              ),
        ),
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

class _UploadDropzone extends StatelessWidget {
  const _UploadDropzone({
    required this.bytes,
    required this.onPick,
    this.stampText,
  });
  final Uint8List? bytes;
  final VoidCallback onPick;
  final String? stampText;

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(bytes!, fit: BoxFit.cover),
                    if (stampText != null && stampText!.trim().isNotEmpty)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            stampText!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
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

class _AssignedProjectInfo extends StatelessWidget {
  const _AssignedProjectInfo({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.instance.projectsCollection.doc(projectId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = (snapshot.data!.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final siteManagerId = (data['siteManagerId'] ?? '').toString();
        final siteManagerName = (data['siteManagerName'] ?? '').toString();

        if (siteManagerId.isEmpty && siteManagerName.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _AiDashboardState._border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _AiDashboardState._border),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person_outline, color: _AiDashboardState._subtitle, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned Site Manager',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._subtitle,
                            letterSpacing: 0.6,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      siteManagerName.isNotEmpty ? siteManagerName : 'Site Manager',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._title,
                          ),
                    ),
                    if (siteManagerId.isNotEmpty)
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseService.instance.usersCollection.doc(siteManagerId).snapshots(),
                        builder: (context, userSnap) {
                          final userData = (userSnap.data?.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
                          final email = (userData['email'] ?? '').toString();
                          if (email.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              email,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _AiDashboardState._navMuted),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
              color: _AiDashboardState._blue,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.description_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GOVTRACK AI REPORT',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
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
                Text(
                  dateText,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
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
  const _ChatComposer({
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    required this.attachmentBytes,
    required this.attachmentName,
    required this.onRemoveImage,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final Uint8List? attachmentBytes;
  final String? attachmentName;
  final VoidCallback onRemoveImage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _AiDashboardState._border),
            boxShadow: _AiDashboardState._shadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachmentBytes != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          attachmentBytes!,
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          (attachmentName ?? 'Image').trim().isEmpty ? 'Image' : attachmentName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: _AiDashboardState._title,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: onRemoveImage,
                        icon: const Icon(Icons.close_rounded, size: 18, color: _AiDashboardState._subtitle),
                        tooltip: 'Remove image',
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  IconButton(
                    onPressed: onPickImage,
                    icon: const Icon(Icons.attach_file, size: 18, color: _AiDashboardState._subtitle),
                    tooltip: 'Attach image',
                  ),
                  const SizedBox(width: 6),
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
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, color: _AiDashboardState._blue),
                  ),
                ],
              ),
            ],
          ),
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
