import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import '../../utils/dialog_utils.dart';
import '../../utils/daily_report_print.dart';
import '../../services/archive_service.dart';
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

    showCenteredDialog<void>(
      context: context,
      maxWidth: 760,
      builder: (dialogContext) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Daily Report - $dateText',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.print_outlined),
                      tooltip: 'Print paper form',
                      onPressed: () {
                        printDailyReportForm(
                          projectName: report.projectId,
                          reporterName: report.reporterId,
                          reportDate: report.reportDate,
                          weather: report.weatherCondition,
                          temperature:
                              '${report.temperatureC.toStringAsFixed(1)}°C',
                          remarks: report.remarks ?? '',
                          accomplishments: [
                            for (final item in report.workAccomplishments)
                              {
                                'description': item.description,
                                'quantity':
                                    '${item.quantityAccomplished} ${item.unit}'
                                        .trim(),
                                'progress':
                                    '${item.percentageComplete.toStringAsFixed(1)}%',
                                'remarks': item.remarks ?? '',
                              },
                          ],
                          issues: report.issues,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Reporter: ${report.reporterId}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'WBS: ${item.wbsCode} • ${item.quantityAccomplished} ${item.unit}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.mediumGray,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Progress: ${item.percentageComplete.toStringAsFixed(1)}%',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (item.remarks != null &&
                                    item.remarks!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Remarks: ${item.remarks}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
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
                  if (report.remarks != null &&
                      report.remarks!.trim().isNotEmpty) ...[
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
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
  bool _isChatSending = false;

  String? _selectedProjectId;
  String? _selectedProjectName;

  final List<Uint8List> _selectedImageBytesList = <Uint8List>[];
  final List<String> _selectedImageNames = <String>[];

  final List<String> _lastAnalyzedImageUrls = <String>[];
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
      text:
          'Tell me what you want to check. I can analyze project progress, materials/inventory, deliveries, attendance, delays, and site risks.',
    ),
  ];

  String _fallbackText() {
    return 'Limited data available for full analysis.';
  }

  @override
  void initState() {
    super.initState();
    _autoSelectSiteManagerProject();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoSelectSiteManagerProject();
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _autoSelectSiteManagerProject();
      });
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to use GovTrack AI.')),
        );
        context.go(RouteNames.login);
      }
    });
  }

  Future<void> _autoSelectSiteManagerProject() async {
    if (widget.showBottomNav != true) return;
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    if ((_selectedProjectId ?? '').trim().isNotEmpty) return;

    String? projectId;
    if (user.assignedProjects.isNotEmpty) {
      projectId = user.assignedProjects.first;
    } else if (user.isSiteManager) {
      return;
    }

    if (projectId == null || projectId.trim().isEmpty) return;

    if (mounted) {
      setState(() {
        _selectedProjectId = projectId;
        _selectedProjectName ??= projectId;
      });
    }

    try {
      final snap = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      final data =
          (snap.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final name =
          (data['name'] ?? data['projectName'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _selectedProjectName = name.isEmpty ? projectId : name;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedProjectName = projectId;
      });
    }
  }

  Future<({String? id, String? name})> _resolveChatProject() async {
    var projectId = (_selectedProjectId ?? '').trim();
    var projectName = (_selectedProjectName ?? '').trim();

    if (projectId.isEmpty) {
      await _autoSelectSiteManagerProject();
      projectId = (_selectedProjectId ?? '').trim();
      projectName = (_selectedProjectName ?? '').trim();
    }

    if (projectId.isEmpty) {
      final user = AuthService.instance.currentUser;
      if (user != null && user.assignedProjects.isNotEmpty) {
        projectId = user.assignedProjects.first;
        if (mounted) {
          setState(() {
            _selectedProjectId = projectId;
            _selectedProjectName ??= projectId;
          });
        }
        try {
          final snap = await FirebaseService.instance.projectsCollection
              .doc(projectId)
              .get();
          final data = (snap.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final name =
              (data['name'] ?? data['projectName'] ?? '').toString().trim();
          projectName = name.isEmpty ? projectId : name;
          if (mounted) {
            setState(() => _selectedProjectName = projectName);
          }
        } catch (_) {
          projectName = projectId;
        }
      }
    }

    return (
      id: projectId.isEmpty ? null : projectId,
      name: projectName.isEmpty ? null : projectName
    );
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
                  final picked = await picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 85);
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
                  final picked = await picker.pickImage(
                      source: ImageSource.camera, imageQuality: 85);
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
                    _selected = i == 0
                        ? _AiNavItem.intelligenceChat
                        : _AiNavItem.imageGenerate;
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
                          _selected = i == 0
                              ? _AiNavItem.intelligenceChat
                              : _AiNavItem.imageGenerate;
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
        const SnackBar(
            content: Text('Please sign in again. Your session expired.')),
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

      final projectDoc = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      final projectData =
          (projectDoc.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      final projectName = _selectedProjectName ??
          (projectData['name'] ?? 'Selected Project').toString();

      final recentDailyReportsQuery = await FirebaseService.instance
          .dailyReportsCollection(projectId)
          .orderBy('reportDate', descending: true)
          .limit(5)
          .get();

      final recentDailyReports = recentDailyReportsQuery.docs
          .map((d) => ((d.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{}))
          .toList();

      final progressPercent = _calculateProgressPercent(recentDailyReports);

      final assignedSiteManagerId =
          (projectData['siteManagerId'] ?? '').toString().trim();
      final assignedSiteManagerName =
          (projectData['siteManagerName'] ?? '').toString().trim();
      final assignedSiteManagerEmail = assignedSiteManagerId.isEmpty
          ? ''
          : await _tryGetUserEmail(assignedSiteManagerId);

      Map<String, dynamic> analysis;
      try {
        final callable = FirebaseFunctions.instance
            .httpsCallable('generateGovTrackReportGemini');
        final res = await callable.call(<String, dynamic>{
          'projectId': projectId,
          'projectName': projectName,
          'projectData': projectData,
          'recentDailyReports': recentDailyReports,
        }).timeout(const Duration(seconds: 60));

        final data =
            (res.data as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        analysis = (data['analysis'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
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

      analysis = <String, dynamic>{
        ...analysis,
        'progressPercent': progressPercent,
      };

      await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .collection('govtrack_reports')
          .add(
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
          'submittedByName':
              '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'
                  .trim(),
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
    final Map<String, double> maxPctByWorkItem = {};

    for (final r in reports) {
      final accomplishments =
          (r['workAccomplishments'] as List?)?.cast<dynamic>() ?? const [];
      for (final raw in accomplishments) {
        final item =
            (raw as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final pct = item['percentageComplete'];
        if (pct is! num) continue;

        final wbs = (item['wbsCode'] ?? '').toString().trim();
        final desc = (item['description'] ?? '').toString().trim();
        final key = wbs.isNotEmpty ? wbs : desc;
        if (key.isEmpty) continue;

        final value = pct.toDouble().clamp(0.0, 100.0).toDouble();
        final current = maxPctByWorkItem[key];
        if (current == null || value > current) {
          maxPctByWorkItem[key] = value;
        }
      }
    }

    if (maxPctByWorkItem.isEmpty) return 0;
    final total = maxPctByWorkItem.values.fold<double>(0, (a, b) => a + b);
    final avg = total / maxPctByWorkItem.length;
    if (avg.isNaN) return 0;
    return avg.clamp(0.0, 100.0).toDouble();
  }

  Future<String> _tryGetUserEmail(String userId) async {
    try {
      final doc =
          await FirebaseService.instance.usersCollection.doc(userId).get();
      final data =
          (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      return (data['email'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Widget _buildChat(BuildContext context) {
    final isMobileSiteManager = widget.showBottomNav == true &&
        (AuthService.instance.currentUser?.isSiteManager ?? false);
    final projectLabel =
        (_selectedProjectName ?? _selectedProjectId ?? '').trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMobileSiteManager && projectLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _blue.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.apartment_outlined,
                          size: 18, color: _blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Project: $projectLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _title,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _Card(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _GovChatBubble(message: _messages[index]),
                      ),
                    ),
                    const Divider(height: 1, color: _border),
                    _ChatComposer(
                      controller: _chatController,
                      onSend: _sendChat,
                      isSending: _isChatSending,
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
                    onPressed:
                        _isGeneratingReport ? null : _generateGovTrackReport,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isGeneratingReport
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      _isGeneratingReport
                          ? 'Generating...'
                          : 'Generate GovTrack Report (Free / Local)',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Runs on this PC via Ollama (127.0.0.1:11434). Generated reports are saved to Firestore.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: _subtitle),
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
                  bytesList: _selectedImageBytesList,
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      _selectedImageBytesList.isEmpty
                          ? 'Upload Photo'
                          : 'Upload Photos (${_selectedImageBytesList.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isAnalyzing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Analyze Image',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _canSubmitProgressToAdmin()
                        ? _submitProgressToAdmin
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Submit to Admin',
                        style: TextStyle(fontWeight: FontWeight.w900)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.insights_outlined,
                            size: 18, color: _AiDashboardState._subtitle),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Progress: ${_lastAnalyzedProgressPercent!.toStringAsFixed(1)}%',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
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
            return const SizedBox.shrink();
          }
          return _GovTrackReportCard(
            projectName: _selectedProjectName ?? 'Selected Project',
            analysis: _lastAnalysis!,
          );
        }

        final data = (docs.first.data() as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final analysis = (data['analysis'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        return _GovTrackReportCard(
          projectName: _selectedProjectName ?? 'Selected Project',
          analysis: analysis,
        );
      },
    );
  }

  Widget _buildProjectDropdown(BuildContext context) {
    final user = AuthService.instance.currentUser;
    var query = FirebaseService.instance.projectsCollection
        .where('status', isEqualTo: 'ongoing');
    if (user != null && user.isSiteManager) {
      query = query.where('siteManagerId', isEqualTo: user.id);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
              height: 56, child: Center(child: CircularProgressIndicator()));
        }

        final docs = (snapshot.data?.docs ?? const []).where((d) {
          final data = (d.data() as Map?)?.cast<String, dynamic>() ?? {};
          return !ArchiveService.isArchived(data);
        }).toList();
        final items = docs
            .map((d) {
              final data = (d.data() as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{};
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
            final data = (first.data() as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            setState(() {
              _selectedProjectId = first.id;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          });
        }

        return DropdownButtonFormField<String>(
          initialValue: items.any((e) => e.value == _selectedProjectId)
              ? _selectedProjectId
              : null,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            final doc =
                docs.firstWhere((e) => e.id == v, orElse: () => docs.first);
            final data = (doc.data() as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            setState(() {
              _selectedProjectId = v;
              _selectedProjectName = (data['name'] ?? '').toString();
            });
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: _cardBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    if (text.isEmpty || _isChatSending) return;

    final isMobileSiteManager = widget.showBottomNav == true &&
        (AuthService.instance.currentUser?.isSiteManager ?? false);

    final resolved = await _resolveChatProject();
    if (isMobileSiteManager && (resolved.id ?? '').trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No project assigned to your account. Ask an admin to assign a project first.'),
        ),
      );
      return;
    }

    final chatProjectId = resolved.id ?? _selectedProjectId;
    final chatProjectName = resolved.name ?? _selectedProjectName;

    final pendingImageBytes = _chatImageBytes;
    final pendingImageName = _chatImageName;

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
      _isChatSending = true;
      _messages.add(_ChatMessage(
        isUser: true,
        text: text,
        imageBytes: pendingImageBytes,
        imageName: pendingImageName,
      ));
      _messages.add(const _ChatMessage(isUser: false, text: 'Thinking…'));
      _chatController.clear();
    });

    try {
      Map<String, dynamic> data;

      List<Map<String, dynamic>> buildRecentHistory() {
        final out = <Map<String, dynamic>>[];
        for (final m in _messages) {
          if (m.isUser == false && m.text.trim() == 'Thinking…') continue;
          final t = m.text.trim();
          if (t.isEmpty) continue;
          out.add(<String, dynamic>{
            'role': m.isUser ? 'user' : 'assistant',
            'text': t,
            'hasImage': m.imageBytes != null,
          });
        }

        if (out.isNotEmpty) {
          final last = out.last;
          if (last['role'] == 'user' &&
              (last['text'] ?? '').toString() == text) {
            out.removeLast();
          }
        }

        const maxTurns = 12;
        if (out.length > maxTurns) {
          return out.sublist(out.length - maxTurns);
        }
        return out;
      }

      String? attachmentUrl;
      String? attachmentStoragePath;
      String? attachmentFileName;

      if (_chatImageBytes != null) {
        final now = DateTime.now();
        final fileName = (_chatImageName?.isNotEmpty ?? false)
            ? _chatImageName!
            : 'chat_image.jpg';
        final safeFileName =
            fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final storagePath =
            'govtrack_chat_attachments/${now.millisecondsSinceEpoch}_$safeFileName';
        final downloadUrl = await FirebaseService.instance.uploadFile(
          storagePath,
          _chatImageBytes!,
          contentType: _guessContentType(fileName),
        );
        attachmentUrl = downloadUrl;
        attachmentStoragePath = storagePath;
        attachmentFileName = fileName;

        if (mounted) {
          setState(() {
            _chatImageBytes = null;
            _chatImageName = null;
          });
        }
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
          debugPrint(
              'govtrack: missing idToken before calling govtrackChatGemini');
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
        final callable =
            FirebaseFunctions.instance.httpsCallable('govtrackChatGemini');
        final res = await callable.call(<String, dynamic>{
          'message': text,
          'history': buildRecentHistory(),
          'idToken': idToken,
          'imageUrl': attachmentUrl,
          'storagePath': attachmentStoragePath,
          'fileName': attachmentFileName,
          'projectId': chatProjectId,
          'projectName': chatProjectName,
        }).timeout(const Duration(seconds: 120));
        debugPrint('govtrack: govtrackChatGemini returned');
        return (res.data as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
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
      final assistantText = reply.isEmpty ? _fallbackText() : reply;

      final currentUser = AuthService.instance.currentUser;
      final fbUser = FirebaseAuth.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_chat',
          'message': text,
          'reply': reply,
          'imageUrl': attachmentUrl,
          'storagePath': attachmentStoragePath,
          'fileName': attachmentFileName,
          'projectId': chatProjectId,
          'projectName': chatProjectName,
          'submittedById': currentUser?.id,
          'submittedByUid': fbUser?.uid,
          'submittedByName':
              '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'
                  .trim(),
          'submittedByEmail': currentUser?.email,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.isUser == false &&
            _messages.last.text == 'Thinking…') {
          _messages.removeLast();
        }
        _messages.add(_ChatMessage(
          isUser: false,
          text: assistantText,
        ));
        _isChatSending = false;
      });
    } catch (e) {
      final u = FirebaseAuth.instance.currentUser;
      final uid = u?.uid;
      final rawMsg = e is FirebaseFunctionsException
          ? 'Chat failed (${e.code}): message=${e.message ?? 'null'} details=${e.details ?? 'null'} (uid: ${uid ?? 'null'})'
          : 'Chat failed: $e (uid: ${uid ?? 'null'})';
      debugPrint('govtrack: $rawMsg');
      developer.log(
        'GovTrack chat failed',
        name: 'govtrack',
        error: rawMsg,
      );
      if (!mounted) return;

      final lower = rawMsg.toLowerCase();
      final isQuota = lower.contains('exceeded your current quota') ||
          lower.contains('insufficient_quota') ||
          lower.contains('billing');
      final isRateLimit = lower.contains('rate limit') ||
          lower.contains('too many requests') ||
          lower.contains('429');
      final userFacing = isQuota
          ? 'AI service quota reached. Please check your AI provider billing/plan, then try again.'
          : (isRateLimit
              ? 'AI service is busy right now. Please wait a moment and try again.'
              : 'AI service is temporarily unavailable. Please try again.');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacing)),
      );
      setState(() {
        _isChatSending = false;
        _chatImageBytes = null;
        _chatImageName = null;
        if (_messages.isNotEmpty &&
            _messages.last.isUser == false &&
            _messages.last.text == 'Thinking…') {
          _messages.removeLast();
        }
        _messages.add(_ChatMessage(isUser: false, text: userFacing));
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
      // On Android/iOS, FilePicker may crash while trying to compress/copy
      // images to a temp file. Use ImagePicker there.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final remaining = 10 - _selectedImageBytesList.length;
        if (remaining <= 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You already selected 10 images.')),
          );
          return;
        }

        final picker = ImagePicker();
        final files = await picker.pickMultiImage(imageQuality: 92);
        if (files.isEmpty) return;

        final bytesList = <Uint8List>[];
        final names = <String>[];
        for (final f in files) {
          if (bytesList.length >= remaining) break;
          final b = await f.readAsBytes();
          if (b.isEmpty) continue;
          bytesList.add(Uint8List.fromList(b));
          names.add(f.name);
        }
        if (bytesList.isEmpty) return;

        if (!mounted) return;
        setState(() {
          _selectedImageBytesList.addAll(bytesList);
          _selectedImageNames.addAll(names);
          _lastAnalyzedProgressPercent = null;
          _lastAnalyzedImageUrls.clear();
          _lastPhotoLat = null;
          _lastPhotoLng = null;
          _lastPhotoAddress = null;
          _lastPhotoCapturedAt = null;
        });
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      if (result.files.length > 10) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select up to 10 images only.')),
        );
        return;
      }

      final bytesList = <Uint8List>[];
      final names = <String>[];
      for (final picked in result.files) {
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        bytesList.add(Uint8List.fromList(bytes));
        names.add(picked.name);
      }
      if (bytesList.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _selectedImageBytesList
          ..clear()
          ..addAll(bytesList);
        _selectedImageNames
          ..clear()
          ..addAll(names);
        _lastAnalyzedProgressPercent = null;
        _lastAnalyzedImageUrls.clear();
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
    if (_lastPhotoLat == null ||
        _lastPhotoLng == null ||
        _lastPhotoCapturedAt == null) {
      return null;
    }

    final d = _lastPhotoCapturedAt!;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final dt =
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year} '
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
          const SnackBar(
              content:
                  Text('Please enable Location services to tag this photo.')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Location permission denied. Photo will not be GPS-tagged.')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      String? address;
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').trim().isNotEmpty) (p.street ?? '').trim(),
            if ((p.locality ?? '').trim().isNotEmpty) (p.locality ?? '').trim(),
            if ((p.administrativeArea ?? '').trim().isNotEmpty)
              (p.administrativeArea ?? '').trim(),
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
        final file = await picker.pickImage(
            source: ImageSource.camera, imageQuality: 92);
        if (file == null) return;
        await _captureAndSetGpsStamp();
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          if (_selectedImageBytesList.length >= 10) {
            return;
          }
          _selectedImageBytesList.add(Uint8List.fromList(bytes));
          _selectedImageNames.add(file.name);
          _lastAnalyzedProgressPercent = null;
          _lastAnalyzedImageUrls.clear();
        });
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Camera upload is supported on mobile devices only.')),
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

    final direct = analysis['progressPercent'] ??
        analysis['progress_percent'] ??
        analysis['progress'];
    if (direct is num) {
      return direct.toDouble().clamp(0.0, 100.0).toDouble();
    }

    final schedule = (analysis['schedule'] as Map?)?.cast<String, dynamic>();
    final schedulePct = schedule?['progressPercent'] ?? schedule?['progress'];
    if (schedulePct is num) {
      return schedulePct.toDouble().clamp(0.0, 100.0).toDouble();
    }
    return null;
  }

  bool _canSubmitProgressToAdmin() {
    return _selectedProjectId != null &&
        _lastAnalysis != null &&
        _lastAnalyzedImageUrls.isNotEmpty;
  }

  Future<void> _submitProgressToAdmin() async {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    if (_lastAnalysis == null) return;
    final progressPercent =
        (_lastAnalyzedProgressPercent ?? 0.0).clamp(0.0, 100.0).toDouble();

    try {
      final projectDoc = await FirebaseService.instance.projectsCollection
          .doc(projectId)
          .get();
      final projectData =
          (projectDoc.data() as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      _selectedProjectName ??
          (projectData['name'] ?? 'Selected Project').toString();

      final projectName = _selectedProjectName ??
          (projectData['name'] ?? 'Selected Project').toString();
      final assignedSiteManagerId =
          (projectData['siteManagerId'] ?? '').toString().trim();
      final assignedSiteManagerName =
          (projectData['siteManagerName'] ?? '').toString().trim();
      final assignedSiteManagerEmail = assignedSiteManagerId.isEmpty
          ? ''
          : await _tryGetUserEmail(assignedSiteManagerId);

      final currentUser = AuthService.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_progress_report',
          'projectId': projectId,
          'projectName': projectName,
          'imageUrl': _lastAnalyzedImageUrls.isNotEmpty
              ? _lastAnalyzedImageUrls.first
              : null,
          'imageUrls': _lastAnalyzedImageUrls,
          'progressPercent': progressPercent,
          'analysis': _lastAnalysis,
          'assignedSiteManagerId': assignedSiteManagerId,
          'assignedSiteManagerName': assignedSiteManagerName,
          'assignedSiteManagerEmail': assignedSiteManagerEmail,
          'submittedByUid': FirebaseAuth.instance.currentUser?.uid,
          'submittedById': currentUser?.id,
          'submittedByName':
              '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'
                  .trim(),
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
    if (_selectedImageBytesList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload 1 to 10 site photos first.')),
      );
      return;
    }

    if (_selectedImageBytesList.length > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select up to 10 images only.')),
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

      await fbUser.getIdToken(true);
      final verifyCallable =
          FirebaseFunctions.instance.httpsCallable('verifyProgressImage');
      final estimateCallable =
          FirebaseFunctions.instance.httpsCallable('estimateProgressPercent');

      final urls = <String>[];
      final perImage = <Map<String, dynamic>>[];
      final progressValues = <double>[];
      final labelsUnion = <String>{};
      final objectsUnion = <String>{};
      final stageTotals = <String, double>{
        'foundation': 0.0,
        'structural': 0.0,
        'roofing': 0.0,
        'walls': 0.0,
      };
      int stageCount = 0;

      for (var i = 0; i < _selectedImageBytesList.length; i++) {
        final now = DateTime.now();
        final rawName = (i < _selectedImageNames.length &&
                _selectedImageNames[i].trim().isNotEmpty)
            ? _selectedImageNames[i]
            : 'site_photo_${i + 1}.jpg';
        final safeFileName =
            rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final storagePath =
            'ai_verifications/${now.millisecondsSinceEpoch}_${i + 1}_$safeFileName';

        final downloadUrl = await FirebaseService.instance.uploadFile(
          storagePath,
          _selectedImageBytesList[i],
          contentType: _guessContentType(rawName),
        );
        urls.add(downloadUrl);

        final results = await Future.wait<dynamic>([
          verifyCallable.call(<String, dynamic>{
            'imageUrl': downloadUrl,
            'projectId': _selectedProjectId,
            'projectName': _selectedProjectName,
            'fileName': rawName,
          }).timeout(const Duration(seconds: 60)),
          estimateCallable.call(<String, dynamic>{
            'imageUrl': downloadUrl,
            'storagePath': storagePath,
            'projectId': _selectedProjectId,
            'projectName': _selectedProjectName,
            'fileName': rawName,
          }).timeout(const Duration(seconds: 60)),
        ]);

        final verifyData = (results[0] as HttpsCallableResult).data;
        final estimateData = (results[1] as HttpsCallableResult).data;

        final verifyMap = (verifyData as Map?)?.cast<String, dynamic>();
        final estimateMap = (estimateData as Map?)?.cast<String, dynamic>();

        final verifyLabels = (verifyMap?['labels'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        final verifyObjects = (verifyMap?['objects'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        labelsUnion.addAll(verifyLabels);
        objectsUnion.addAll(verifyObjects);

        final stageProgress =
            (verifyMap?['stageProgress'] as Map?)?.cast<String, dynamic>();
        if (stageProgress != null && stageProgress.isNotEmpty) {
          double readNum(dynamic v) {
            if (v is num) return v.toDouble();
            return double.tryParse(v?.toString() ?? '') ?? 0.0;
          }

          stageTotals['foundation'] = (stageTotals['foundation'] ?? 0) +
              readNum(stageProgress['foundation']);
          stageTotals['structural'] = (stageTotals['structural'] ?? 0) +
              readNum(stageProgress['structural']);
          stageTotals['roofing'] =
              (stageTotals['roofing'] ?? 0) + readNum(stageProgress['roofing']);
          stageTotals['walls'] =
              (stageTotals['walls'] ?? 0) + readNum(stageProgress['walls']);
          stageCount++;
        }

        final ocrProgress =
            estimateMap == null ? null : estimateMap['progressPercent'];
        final ocrProgressPercent = (ocrProgress is num)
            ? ocrProgress.toDouble().clamp(0.0, 100.0).toDouble()
            : null;

        final fallbackPercent = _extractProgressPercentFromAnalysis(verifyMap);
        final pct = ocrProgressPercent ?? fallbackPercent;
        if (pct != null) {
          progressValues.add(pct);
        }

        perImage.add(<String, dynamic>{
          'imageUrl': downloadUrl,
          'fileName': rawName,
          'storagePath': storagePath,
          'analysis': verifyMap,
          'ocr': estimateMap,
          'progressPercent': pct,
        });
      }

      final avg = progressValues.isEmpty
          ? null
          : (progressValues.reduce((a, b) => a + b) / progressValues.length)
              .clamp(0.0, 100.0)
              .toDouble();

      Map<String, dynamic>? aggregatedStageProgress;
      if (stageCount > 0) {
        double mean(String k) =>
            ((stageTotals[k] ?? 0.0) / stageCount).clamp(0.0, 100.0).toDouble();
        aggregatedStageProgress = <String, dynamic>{
          'foundation': mean('foundation'),
          'structural': mean('structural'),
          'roofing': mean('roofing'),
          'walls': mean('walls'),
        };
      }

      double? overall;
      if (avg != null) {
        overall = avg;
      } else if (aggregatedStageProgress != null) {
        final values = <double>[
          (aggregatedStageProgress['foundation'] as num).toDouble(),
          (aggregatedStageProgress['structural'] as num).toDouble(),
          (aggregatedStageProgress['roofing'] as num).toDouble(),
          (aggregatedStageProgress['walls'] as num).toDouble(),
        ];
        overall = (values.reduce((a, b) => a + b) / values.length)
            .clamp(0.0, 100.0)
            .toDouble();
      }

      final mergedAnalysis = <String, dynamic>{
        'progressPercent': overall,
        if (aggregatedStageProgress != null)
          'stageProgress': aggregatedStageProgress,
        'labels': labelsUnion.toList(),
        'objects': objectsUnion.toList(),
        'imagesAnalyzed': perImage,
      };

      setState(() {
        _lastAnalysis = mergedAnalysis;
        _lastAnalyzedImageUrls
          ..clear()
          ..addAll(urls);
        _lastAnalyzedProgressPercent = overall;
      });

      final currentUser = AuthService.instance.currentUser;
      final fbAuthUser = FirebaseAuth.instance.currentUser;
      await FirebaseService.instance.aiAnalysisCollection.add(
        <String, dynamic>{
          'kind': 'govtrack_image_analysis',
          'projectId': _selectedProjectId,
          'projectName': _selectedProjectName,
          'imageUrl': urls.isNotEmpty ? urls.first : null,
          'imageUrls': urls,
          'progressPercent': avg,
          'submittedByUid': fbAuthUser?.uid,
          'submittedById': currentUser?.id,
          'submittedByName': currentUser?.displayName,
          'submittedByEmail': currentUser?.email,
          'analysis': mergedAnalysis,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analysis complete.')),
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
    final displayName =
        '${currentUser?.firstName ?? ''} ${currentUser?.lastName ?? ''}'.trim();
    final email = (currentUser?.email ?? '').trim();
    final initialsSource = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email : 'User');
    final parts = initialsSource
        .split(RegExp(r'\s+|\.|\-|\_'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? 'U'
        : (parts.first[0] + (parts.length > 1 ? parts[1][0] : ''))
            .toUpperCase();

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
                  child: const Icon(Icons.shield_outlined,
                      color: Colors.white, size: 18),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: _AiDashboardState._navMuted),
                      )
                    else
                      StreamBuilder<QuerySnapshot>(
                        stream: (() {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null && uid.trim().isNotEmpty) {
                            return FirebaseService.instance.aiAnalysisCollection
                                .where('submittedByUid', isEqualTo: uid)
                                .limit(30)
                                .snapshots();
                          }
                          // Fallback for older sessions/docs that only store submittedById
                          return FirebaseService.instance.aiAnalysisCollection
                              .where('submittedById', isEqualTo: currentUser.id)
                              .limit(30)
                              .snapshots();
                        })(),
                        builder: (context, snapshot) {
                          final docs = snapshot.data?.docs ?? const [];
                          final filtered = docs.where((d) {
                            final data =
                                (d.data() as Map?)?.cast<String, dynamic>() ??
                                    <String, dynamic>{};
                            final kind = (data['kind'] ?? '').toString();
                            return kind == 'govtrack_chat' ||
                                kind == 'govtrack_image_analysis' ||
                                kind == 'govtrack_progress_report';
                          }).toList()
                            ..sort((a, b) {
                              DateTime? toDt(dynamic v) {
                                if (v is Timestamp) return v.toDate();
                                if (v is DateTime) return v;
                                return null;
                              }

                              final ad =
                                  (a.data() as Map?)?.cast<String, dynamic>() ??
                                      <String, dynamic>{};
                              final bd =
                                  (b.data() as Map?)?.cast<String, dynamic>() ??
                                      <String, dynamic>{};
                              final at = toDt(ad['createdAt']);
                              final bt = toDt(bd['createdAt']);
                              if (at == null && bt == null) return 0;
                              if (at == null) return 1;
                              if (bt == null) return -1;
                              return bt.compareTo(at);
                            });

                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Loading history…',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: _AiDashboardState._navMuted),
                              ),
                            );
                          }

                          if (filtered.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No AI history yet.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: _AiDashboardState._navMuted),
                              ),
                            );
                          }

                          return Column(
                            children: [
                              for (final doc in filtered) ...[
                                Builder(
                                  builder: (context) {
                                    final data = (doc.data() as Map?)
                                            ?.cast<String, dynamic>() ??
                                        <String, dynamic>{};
                                    final kind =
                                        (data['kind'] ?? '').toString();
                                    final title = _kindLabel(kind);
                                    final projectName =
                                        (data['projectName'] ?? '')
                                            .toString()
                                            .trim();
                                    final when =
                                        _formatDateTime(data['createdAt']);
                                    final message = (data['message'] ?? '')
                                        .toString()
                                        .trim();

                                    final subtitleParts = <String>[
                                      if (projectName.isNotEmpty) projectName,
                                      if (when.isNotEmpty) when,
                                      if (kind == 'govtrack_chat' &&
                                          message.isNotEmpty)
                                        message,
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
                                      subtitle:
                                          subtitle.isEmpty ? null : subtitle,
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
                        displayName.isEmpty ? 'Resident Engineer' : displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AiDashboardState._title,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.isEmpty ? '—' : email,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: _AiDashboardState._navMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.logout,
                      color: _AiDashboardState._navMuted, size: 18),
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
                  color: active
                      ? _AiDashboardState._navActiveAccent
                      : Colors.black.withValues(alpha: 0.75),
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
                              color: active
                                  ? _AiDashboardState._title
                                  : Colors.black.withValues(alpha: 0.78),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              tooltip: 'Menu',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'GovTrack AI',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
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
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                        child:
                            _PillTabs(index: tabIndex, onChange: onTabChange),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
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
                                      prefixIcon:
                                          const Icon(Icons.search, size: 20),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12),
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
                                _PillTabs(
                                    index: tabIndex, onChange: onTabChange),
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
            _PillTab(
                text: 'Intelligence Chat',
                active: index == 0,
                onTap: () => onChange(0)),
            _PillTab(
                text: 'AI Daily Progress',
                active: index == 1,
                onTap: () => onChange(1)),
          ],
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab(
      {required this.text, required this.active, required this.onTap});
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
              color: active
                  ? _AiDashboardState._navActiveAccent
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: active
                    ? _AiDashboardState._navActiveAccent
                    : _AiDashboardState._subtitle,
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
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: _AiDashboardState._subtitle),
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
    required this.bytesList,
    required this.onPick,
    this.stampText,
  });
  final List<Uint8List> bytesList;
  final VoidCallback onPick;
  final String? stampText;

  @override
  Widget build(BuildContext context) {
    void showViewer(int initialIndex) {
      showDialog<void>(
        context: context,
        builder: (c) {
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 860,
              height: 640,
              child: PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: bytesList.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 6,
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: Image.memory(
                        bytesList[index],
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    return InkWell(
      onTap: bytesList.isEmpty ? onPick : () => showViewer(0),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 340,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AiDashboardState._blue, width: 1.2),
        ),
        child: bytesList.isEmpty
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
                      child: const Icon(Icons.photo_camera_outlined,
                          color: _AiDashboardState._blue, size: 26),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Upload Site Photo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._title,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Drag & drop or click to browse',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _AiDashboardState._subtitle,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'JPG, PNG • Max 10MB • Geo-tag preferred',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _AiDashboardState._subtitle,
                          ),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(bytesList.first, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: onPick,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_photo_alternate_outlined,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Add (${bytesList.length}/10)',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (bytesList.length > 1)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: (stampText ?? '').trim().isNotEmpty ? 88 : 12,
                      child: SizedBox(
                        height: 62,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: bytesList.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return InkWell(
                              onTap: () => showViewer(index),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 62,
                                      height: 62,
                                      color:
                                          Colors.white.withValues(alpha: 0.12),
                                      child: Image.memory(bytesList[index],
                                          fit: BoxFit.cover),
                                    ),
                                    Positioned(
                                      right: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  if ((stampText ?? '').trim().isNotEmpty)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      right: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            stampText!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AssignedProjectInfo extends StatelessWidget {
  const _AssignedProjectInfo({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.instance.projectsCollection
          .doc(projectId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = (snapshot.data!.data() as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
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
                child: const Icon(Icons.person_outline,
                    color: _AiDashboardState._subtitle, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned Resident Engineer',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._subtitle,
                            letterSpacing: 0.6,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      siteManagerName.isNotEmpty
                          ? siteManagerName
                          : 'Resident Engineer',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _AiDashboardState._title,
                          ),
                    ),
                    if (siteManagerId.isNotEmpty)
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseService.instance.usersCollection
                            .doc(siteManagerId)
                            .snapshots(),
                        builder: (context, userSnap) {
                          final userData = (userSnap.data?.data() as Map?)
                                  ?.cast<String, dynamic>() ??
                              <String, dynamic>{};
                          final email = (userData['email'] ?? '').toString();
                          if (email.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              email,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: _AiDashboardState._navMuted),
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
  const _GovTrackReportCard(
      {required this.projectName, required this.analysis});
  final String projectName;
  final Map<String, dynamic> analysis;

  @override
  Widget build(BuildContext context) {
    final confidence =
        ((analysis['confidence'] ?? 0.0) as num).toDouble().clamp(0.0, 1.0);
    final confPct = (confidence * 100).round();
    final pass = (analysis['pass'] ?? false) == true;
    final date = DateTime.now();
    final dateText =
        '${_monthName(date.month)} ${date.day}, ${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    List<Map<String, dynamic>> readMapList(dynamic value) {
      final raw = value is List ? value : const <dynamic>[];
      return raw
          .map((e) => (e as Map?)?.cast<String, dynamic>())
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    String readString(dynamic v) => (v ?? '').toString().trim();

    final tasks = readMapList(
      analysis['tasks'] ?? analysis['actionItems'] ?? analysis['action_items'],
    );
    final delaySignals = readMapList(
      analysis['delaySignals'] ?? analysis['delay_signals'],
    );
    final materialShortages = readMapList(
      analysis['materialShortages'] ?? analysis['material_shortages'],
    );

    final risks = readMapList(
      analysis['risks'] ?? analysis['riskItems'] ?? analysis['risk_items'],
    );
    final recommendations = readMapList(
      analysis['recommendations'] ??
          analysis['recommendationItems'] ??
          analysis['recommendation_items'],
    );

    List<Map<String, dynamic>> keepWithEvidence(
        List<Map<String, dynamic>> items) {
      return items.where((e) => readString(e['evidence']).isNotEmpty).toList();
    }

    final tasksSafe = keepWithEvidence(tasks);
    final delaySignalsSafe = keepWithEvidence(delaySignals);
    final materialShortagesSafe = keepWithEvidence(materialShortages);
    final risksSafe = keepWithEvidence(risks);
    final recommendationsSafe = keepWithEvidence(recommendations);

    final stages = _inferStages(analysis);
    final schedule = (analysis['schedule'] as Map?)?.cast<String, dynamic>();
    final scheduleDelta =
        (schedule?['deltaPercent'] ?? (pass ? '+1%' : '-2%')).toString();
    final scheduleStatus =
        (schedule?['status'] ?? (pass ? 'On Schedule' : 'Behind Schedule'))
            .toString();
    final scheduleOk = scheduleDelta.trim().startsWith('+') ||
        scheduleStatus.toLowerCase().contains('on');
    final rawProgress = analysis['progressPercent'] ??
        analysis['progress_percent'] ??
        analysis['progress'];
    final progressPercent = rawProgress is num
        ? rawProgress.toDouble().clamp(0.0, 100.0).toDouble()
        : 0.0;
    final estCompletion = progressPercent.round();

    final plannedRaw = analysis['plannedPercent'] ??
        analysis['planned_percent'] ??
        analysis['planned'] ??
        35;
    final plannedPercent = plannedRaw is num
        ? plannedRaw.toDouble().clamp(0.0, 100.0).toDouble()
        : 35.0;

    final daysRaw = analysis['daysRemaining'] ?? analysis['days_remaining'];
    final daysRemaining = daysRaw is num ? daysRaw.toInt() : null;

    final summary = (analysis['summary'] ?? '').toString().trim();

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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: const BoxDecoration(
              color: _AiDashboardState._blue,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: scheduleOk
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$scheduleStatus $scheduleDelta',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 112,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 112,
                            height: 112,
                            child: CircularProgressIndicator(
                              value: (estCompletion / 100.0).clamp(0.0, 1.0),
                              strokeWidth: 10,
                              backgroundColor: const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheduleOk
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                          Text(
                            '$estCompletion%',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall Progress',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '(${plannedPercent.toStringAsFixed(0)}% planned)',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: _AiDashboardState._subtitle,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 10),
                          _PlannedActualBar(
                            planned: plannedPercent,
                            actual: progressPercent,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.schedule,
                        iconBg: const Color(0xFFEFF6FF),
                        iconColor: const Color(0xFF16A34A),
                        title: 'Schedule\nVariance',
                        value: scheduleDelta,
                        subValue: scheduleStatus,
                        valueColor: scheduleOk
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.verified_user,
                        iconBg: const Color(0xFFF1F5F9),
                        iconColor: _AiDashboardState._blue,
                        title: 'Confidence\nScore',
                        value: '$confPct%',
                        subValue: 'Structural',
                        valueColor: pass
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.calendar_month,
                        iconBg: const Color(0xFFF1F5F9),
                        iconColor: _AiDashboardState._blue,
                        title: 'Days\nRemaining',
                        value: daysRemaining == null ? '—' : '$daysRemaining',
                        subValue: 'Remaining',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _AiDashboardState._border),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONSTRUCTION STAGE',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: _AiDashboardState._title,
                              letterSpacing: 0.4,
                            ),
                      ),
                      const SizedBox(height: 12),
                      for (final s in stages) ...[
                        _StageProgressRow(stage: s),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 6),
                      Container(height: 1, color: _AiDashboardState._border),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.lightbulb_outline,
                              color: _AiDashboardState._blue, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'AI Insight',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        summary.isEmpty ? 'Insufficient data.' : summary,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AiDashboardState._subtitle,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _AiDashboardState._subtitle,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (risksSafe.isNotEmpty ||
                          recommendationsSafe.isNotEmpty ||
                          tasksSafe.isNotEmpty ||
                          delaySignalsSafe.isNotEmpty ||
                          materialShortagesSafe.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: _AiDashboardState._border),
                        const SizedBox(height: 12),
                      ],
                      if (risksSafe.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.report_problem_outlined,
                                color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Risks',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final r in risksSafe.take(4)) ...[
                          Text(
                            readString(r['risk']).isEmpty
                                ? readString(r['title'])
                                : readString(r['risk']),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                          if (readString(r['impact']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Impact: ${readString(r['impact'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (readString(r['evidence']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Evidence: ${readString(r['evidence'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 2),
                      ],
                      if (recommendationsSafe.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: _AiDashboardState._blue, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Recommendations',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final rec in recommendationsSafe.take(4)) ...[
                          Text(
                            readString(rec['recommendation']).isEmpty
                                ? readString(rec['title'])
                                : readString(rec['recommendation']),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                          if (readString(rec['rationale']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Rationale: ${readString(rec['rationale'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (readString(rec['evidence']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Evidence: ${readString(rec['evidence'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 2),
                      ],
                      if (tasksSafe.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.task_alt,
                                color: _AiDashboardState._blue, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Recommended Tasks',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final t in tasksSafe.take(5)) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              Expanded(
                                child: Text(
                                  readString(t['title']).isEmpty
                                      ? readString(t['task'])
                                      : readString(t['title']),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: _AiDashboardState._subtitle,
                                        height: 1.25,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          if (readString(t['evidence']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 18, top: 2),
                              child: Text(
                                'Evidence: ${readString(t['evidence'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 6),
                        ],
                        const SizedBox(height: 10),
                      ],
                      if (delaySignalsSafe.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFF59E0B), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Delay Signals',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final s in delaySignalsSafe.take(4)) ...[
                          Text(
                            readString(s['signal']).isEmpty
                                ? readString(s['title'])
                                : readString(s['signal']),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                          if (readString(s['evidence']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Evidence: ${readString(s['evidence'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (materialShortagesSafe.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Material Shortage Risks',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: _AiDashboardState._title,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final m in materialShortagesSafe.take(4)) ...[
                          Text(
                            readString(m['material']).isEmpty
                                ? readString(m['name'])
                                : readString(m['material']),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: _AiDashboardState._title,
                                ),
                          ),
                          if (readString(m['evidence']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Evidence: ${readString(m['evidence'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (readString(m['suggestedAction']).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Action: ${readString(m['suggestedAction'])}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _AiDashboardState._subtitle,
                                      height: 1.25,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          const SizedBox(height: 10),
                        ],
                      ],
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

class _PlannedActualBar extends StatelessWidget {
  const _PlannedActualBar({
    required this.planned,
    required this.actual,
  });

  final double planned;
  final double actual;

  @override
  Widget build(BuildContext context) {
    final p = (planned / 100.0).clamp(0.0, 1.0);
    final a = (actual / 100.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Stack(
              children: [
                Container(color: const Color(0xFFE2E8F0)),
                FractionallySizedBox(
                  widthFactor: p,
                  child: Container(color: const Color(0xFF16A34A)),
                ),
                FractionallySizedBox(
                  widthFactor: a,
                  child: Container(color: const Color(0xFFFACC15)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFF16A34A), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('Planned',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AiDashboardState._subtitle,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('${planned.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AiDashboardState._title,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 14),
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFFFACC15), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('${actual.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _AiDashboardState._title,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subValue,
    this.valueColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;
  final String subValue;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _AiDashboardState._border),
        boxShadow: _AiDashboardState._shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: iconBg, borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _AiDashboardState._subtitle,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? _AiDashboardState._title,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AiDashboardState._subtitle,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _StageProgressRow extends StatelessWidget {
  const _StageProgressRow({required this.stage});

  final _StageItem stage;

  double _progress() {
    final m = RegExp(r'(\d+)\s*%').firstMatch(stage.statusText);
    if (m != null) {
      final pct = double.tryParse(m.group(1) ?? '0') ?? 0.0;
      return (pct / 100.0).clamp(0.0, 1.0);
    }
    return stage.isComplete ? 1.0 : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress();
    final isComplete = stage.isComplete;
    final barColor = isComplete
        ? const Color(0xFF16A34A)
        : (p > 0 ? const Color(0xFFFACC15) : const Color(0xFFE2E8F0));

    return Row(
      children: [
        Icon(
          isComplete ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: isComplete ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Text(
            stage.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AiDashboardState._title,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 46,
          child: Text(
            stage.statusText,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AiDashboardState._subtitle,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ],
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.onSend,
    this.isSending = false,
    required this.onPickImage,
    required this.attachmentBytes,
    required this.attachmentName,
    required this.onRemoveImage,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isSending;
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
                          (attachmentName ?? 'Image').trim().isEmpty
                              ? 'Image'
                              : attachmentName!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: _AiDashboardState._title,
                                  ),
                        ),
                      ),
                      IconButton(
                        onPressed: onRemoveImage,
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: _AiDashboardState._subtitle),
                        tooltip: 'Remove image',
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  IconButton(
                    onPressed: isSending ? null : onPickImage,
                    icon: const Icon(Icons.attach_file,
                        size: 18, color: _AiDashboardState._subtitle),
                    tooltip: 'Attach image',
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: !isSending,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Ask GovTrack AI...',
                      ),
                      onSubmitted: isSending ? null : (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: isSending ? null : onSend,
                    icon: isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _AiDashboardState._blue),
                          )
                        : const Icon(Icons.send_rounded,
                            color: _AiDashboardState._blue),
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
  const _ChatMessage({
    required this.isUser,
    required this.text,
    this.imageBytes,
    this.imageName,
  });
  final bool isUser;
  final String text;
  final Uint8List? imageBytes;
  final String? imageName;
}

class _GovChatBubble extends StatelessWidget {
  const _GovChatBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isThinking = !isUser && message.text.trim() == 'Thinking…';

    final bubbleColor = isUser ? _AiDashboardState._blue : Colors.white;
    final textColor = isUser ? Colors.white : _AiDashboardState._title;
    final border = isUser ? Colors.transparent : _AiDashboardState._border;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
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
            child: const Icon(Icons.smart_toy_outlined,
                color: _AiDashboardState._blue, size: 18),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.imageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      message.imageBytes!,
                      width: 220,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (isThinking)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              isUser ? Colors.white : _AiDashboardState._blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Thinking…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            height: 1.35,
                            fontWeight: FontWeight.w800),
                      ),
                    ],
                  )
                else
                  Text(
                    message.text,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: textColor, height: 1.35),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StageItem {
  const _StageItem(
      this.name, this.statusText, this.statusColor, this.isComplete);
  final String name;
  final String statusText;
  final Color statusColor;
  final bool isComplete;
}

List<_StageItem> _inferStages(Map<String, dynamic> analysis) {
  final stageProgressRaw =
      (analysis['stageProgress'] as Map?)?.cast<String, dynamic>();
  if (stageProgressRaw != null && stageProgressRaw.isNotEmpty) {
    double readPct(String key) {
      final v = stageProgressRaw[key];
      if (v is num) return v.toDouble().clamp(0.0, 100.0).toDouble();
      return double.tryParse(v?.toString() ?? '')
              ?.clamp(0.0, 100.0)
              .toDouble() ??
          0.0;
    }

    _StageItem item(String name, double pct) {
      final rounded = pct.round();
      final complete = rounded >= 100;
      final started = rounded > 0;
      final statusText = complete ? '100%' : (started ? '$rounded%' : '0%');
      final color = complete
          ? const Color(0xFF16A34A)
          : (started ? const Color(0xFFFACC15) : _AiDashboardState._subtitle);
      return _StageItem(name, statusText, color, complete);
    }

    final foundation = readPct('foundation');
    final structural = readPct('structural');
    final roofing = readPct('roofing');
    final walls = readPct('walls');

    return [
      item('Foundation', foundation),
      item('Structural', structural),
      item('Roofing', roofing),
      item('Walls', walls),
    ];
  }

  final labels = (analysis['labels'] is List)
      ? (analysis['labels'] as List)
          .map((e) => e.toString().toLowerCase())
          .toList()
      : <String>[];
  final hasFoundation =
      labels.any((e) => e.contains('concrete') || e.contains('foundation'));
  final hasRoof = labels.any((e) => e.contains('roof'));
  final hasWall = labels.any((e) => e.contains('wall') || e.contains('brick'));
  final hasColumn =
      labels.any((e) => e.contains('column') || e.contains('beam'));

  return [
    _StageItem(
        'Foundation',
        hasFoundation ? 'Completed' : 'Not started',
        hasFoundation ? const Color(0xFF16A34A) : _AiDashboardState._subtitle,
        hasFoundation),
    _StageItem(
        'Structural Columns',
        hasColumn ? 'Completed' : 'Not started',
        hasColumn ? const Color(0xFF16A34A) : _AiDashboardState._subtitle,
        hasColumn),
    _StageItem('Roofing', hasRoof ? '10% complete' : 'Not started',
        _AiDashboardState._subtitle, false),
    _StageItem('Walls', hasWall ? 'In progress' : 'Not started',
        _AiDashboardState._subtitle, false),
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
