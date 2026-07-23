import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/govtrack_ai_prompt.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/govtrack_progress_ml_service.dart';
import '../../services/site_weather_context_service.dart';
import '../../widgets/common/construction_progress_panel.dart';
import '../../widgets/common/site_weather_conditions_card.dart';
import 'widgets/site_manager_bottom_nav.dart';

/// Site Manager GovTrack: AI Assistant (text chat) + AI Progress Analysis (ML images).
class SiteManagerGovtrackScreen extends StatefulWidget {
  const SiteManagerGovtrackScreen({
    super.key,
    this.initialTab = 0,
    this.showBottomNav = true,
  });

  final int initialTab;
  final bool showBottomNav;

  @override
  State<SiteManagerGovtrackScreen> createState() => _SiteManagerGovtrackScreenState();
}

class _SiteManagerGovtrackScreenState extends State<SiteManagerGovtrackScreen>
    with SingleTickerProviderStateMixin {
  static const Color _purple = Color(0xFF7C3AED);
  static const Color _headerBlue = Color(0xFF1E3A8A);

  late final TabController _tabs;

  // Chat
  final _chatController = TextEditingController();
  final _chatScroll = ScrollController();
  final List<_ChatMsg> _messages = [
    const _ChatMsg(
      isUser: false,
      text:
          "Hi! I'm GovTrack AI 👋 I help with (1) construction & safety guidance, (2) live materials tracking, and (3) project progress & timelines — using your project data, weather, and uploaded SOPs only. Missing metrics? I'll tell you.",
    ),
  ];
  bool _chatSending = false;
  String? _progressError;
  String? _projectId;
  String? _projectName;
  String? _projectLocation;
  SiteWeatherBundle? _weatherBundle;

  // Progress analysis
  final _imagePicker = ImagePicker();
  final List<Uint8List> _photoBytes = [];
  final List<String> _photoNames = [];
  bool _analyzing = false;
  int _progressStep = 0;
  GovtrackMlAnalysisResult? _mlResult;
  Map<String, dynamic>? _lastAnalysisMap;

  final _mlService = GovtrackProgressMlService();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _loadProject();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshWeather({bool force = false}) async {
    try {
      final bundle = await SiteWeatherContextService.instance.load(
        projectLocation: _projectLocation,
        forceRefresh: force,
      );
      if (mounted) setState(() => _weatherBundle = bundle);
    } catch (_) {}
  }

  bool _isWeatherQuestion(String text) {
    final m = text.toLowerCase();
    return m.contains('weather') ||
        m.contains('temperature') ||
        m.contains('forecast') ||
        m.contains('rain') ||
        m.contains('humidity') ||
        m.contains('wind') ||
        m.contains('hot') ||
        m.contains('cold');
  }

  String _localWeatherReply(SiteWeatherBundle bundle) {
    final live = bundle.liveReport;
    if (live != null && live.isOffline) {
      return GovtrackAiPrompt.weatherOfflineReply;
    }
    if (live != null && !live.hasError) {
      final lines = <String>[
        'Right now at ${bundle.locationLabel}: ${live.temperature}, humidity ${live.humidity}.',
        'Visibility: ${live.environmentLighting}.',
        live.rainForecast,
        if (!live.isDaylight)
          'Reminder: check site lighting and wear high-visibility PPE.',
        if (live.rainIsComing)
          'Cover cement, drywall, and open electrical work before rain arrives.',
      ];
      return lines.where((s) => s.trim().isNotEmpty).join('\n');
    }
    final now = bundle.now;
    final lines = <String>[
      'Right now at ${bundle.locationLabel}: ${now.temperatureC.toStringAsFixed(0)}°C, ${now.description}.',
      if (now.feelsLikeC != null) 'Feels like ${now.feelsLikeC!.toStringAsFixed(0)}°C.',
      if (now.humidity != null) 'Humidity ${now.humidity}%.',
      if (bundle.forecastDays.isNotEmpty)
        'Today’s high ${bundle.forecastDays.first.maxTempC.toStringAsFixed(0)}°C / low ${bundle.forecastDays.first.minTempC.toStringAsFixed(0)}°C.',
      bundle.siteAdvice,
    ];
    return lines.where((s) => s.trim().isNotEmpty).join('\n');
  }

  Future<void> _loadProject() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.assignedProjects.isEmpty) return;
    final id = user.assignedProjects.first;
    String name = id;
    try {
      final snap = await FirebaseService.instance.projectsCollection.doc(id).get();
      final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
      final n = (data['name'] ?? data['projectName'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
      final loc = (data['location'] ?? '').toString().trim();
      _projectLocation = loc.isEmpty ? null : loc;
    } catch (_) {}
    await _refreshWeather();
    if (!mounted) return;
    setState(() {
      _projectId = id;
      _projectName = name;
    });
  }

  Future<bool> _ensureAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again.')),
      );
      return false;
    }
    try {
      await user.getIdToken(true);
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot refresh session. Check your connection.')),
      );
      return false;
    }
  }

  List<Map<String, dynamic>> _chatHistoryPayload() {
    return _messages
        .where((m) => m.text != 'Thinking…' && m.text.isNotEmpty)
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'text': m.displayText,
            })
        .toList()
        .reversed
        .take(24)
        .toList()
        .reversed
        .toList();
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied')) {
      return 'Permission denied. Ask your admin to confirm project assignment, then try again.';
    }
    if (s.contains('unauthenticated')) {
      return 'Session expired. Please sign in again.';
    }
    if (s.contains('deadline-exceeded') || s.contains('TimeoutException')) {
      return 'Request timed out. Check your connection and retry.';
    }
    return s.replaceFirst(RegExp(r'^Exception:\s*'), '').replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _chatSending) return;
    if (!await _ensureAuth()) return;

    setState(() {
      _chatSending = true;
      _messages.add(_ChatMsg(isUser: true, text: text));
      _messages.add(const _ChatMsg(isUser: false, text: 'Thinking…'));
      _chatController.clear();
    });
    _scrollChatToEnd();

    try {
      await _refreshWeather(force: true);
      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken(true);
      final callable = FirebaseFunctions.instance.httpsCallable('govtrackChatGemini');
      final res = await callable
          .call(<String, dynamic>{
        'message': text,
        'history': _chatHistoryPayload(),
        'idToken': idToken,
        'projectId': _projectId,
        'projectName': _projectName,
        if (_weatherBundle != null) 'weatherContext': _weatherBundle!.toAiJson(),
      })
          .timeout(const Duration(seconds: 120));

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      var rawReply = (data['reply'] ?? data['message'] ?? '').toString().trim();
      if (_isWeatherQuestion(text) &&
          _weatherBundle != null &&
          (rawReply.toLowerCase().contains('cannot find') ||
              rawReply.toLowerCase().contains('tracking metric') ||
              rawReply.toLowerCase().contains('not in the current project'))) {
        rawReply = _localWeatherReply(_weatherBundle!);
      }
      final parsed = _GovtrackParsedReply.fromRaw(rawReply);

      if (!mounted) return;
      setState(() {
        _removeThinking();
        _messages.add(_ChatMsg.fromParsed(parsed));
        _chatSending = false;
      });
      _scrollChatToEnd();

      try {
        await FirebaseService.instance.aiAnalysisCollection.add({
          'kind': 'govtrack_chat',
          'message': text,
          'reply': rawReply,
          if (_projectId != null) 'projectId': _projectId,
          if (_projectName != null) 'projectName': _projectName,
          'submittedByUid': user?.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (logErr) {
        developer.log('govtrack chat log skipped', error: logErr);
      }
    } catch (e) {
      developer.log('govtrack chat error', error: e);
      if (!mounted) return;
      setState(() {
        _removeThinking();
        _messages.add(_ChatMsg(isUser: false, text: _friendlyError(e)));
        _chatSending = false;
      });
      _scrollChatToEnd();
    }
  }

  void _removeThinking() {
    if (_messages.isNotEmpty && !_messages.last.isUser && _messages.last.text == 'Thinking…') {
      _messages.removeLast();
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _insertChatPrompt(String text) {
    _chatController.text = text;
    _tabs.animateTo(0);
    _sendChat();
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 85);
      if (!mounted) return;
      if (files.isEmpty) return;
      final room = 10 - _photoBytes.length;
      if (room <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 10 images.')),
        );
        return;
      }
      for (final f in files.take(room)) {
        final bytes = await f.readAsBytes();
        _photoBytes.add(bytes);
        _photoNames.add(f.name);
      }
      setState(() {
        _progressStep = 0;
        _mlResult = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick images: $e')),
      );
    }
  }

  Future<void> _runMlAnalysis() async {
    if (_projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project assigned.')),
      );
      return;
    }
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload 1 to 10 site photos first.')),
      );
      return;
    }
    if (!await _ensureAuth()) return;

    setState(() {
      _analyzing = true;
      _progressStep = 1;
      _progressError = null;
    });

    try {
      final result = await _mlService.analyzeSitePhotos(
        projectId: _projectId!,
        projectName: _projectName,
        imageBytesList: _photoBytes,
        imageNames: _photoNames,
      );

      final analysisMap = result.toAnalysisMap();
      final pct = result.overallProgressPercent;

      String? syncWarning;
      if (pct != null && _projectId != null) {
        try {
          await FirebaseService.instance.projectsCollection.doc(_projectId!).update({
            'progressPercentage': pct,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          syncWarning =
              'Analysis saved locally; project % not synced (${_friendlyError(e)}). Deploy updated Firestore rules.';
          developer.log('progress sync failed', error: e);
        }
      }

      if (!mounted) return;
      setState(() {
        _mlResult = result;
        _lastAnalysisMap = analysisMap;
        _analyzing = false;
        _progressStep = 2;
        _progressError = syncWarning;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pct == null
                ? 'Analysis complete (no % detected).'
                : 'ML analysis: ${pct.toStringAsFixed(0)}% overall',
          ),
          backgroundColor: AppTheme.softGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _progressStep = 0;
        _progressError = _friendlyError(e);
      });
    }
  }

  Future<void> _sendToAdmin() async {
    if (_projectId == null || _mlResult == null) return;
    final pct = (_mlResult!.overallProgressPercent ?? 0).clamp(0, 100);
    final user = AuthService.instance.currentUser;
    try {
      await FirebaseService.instance.aiAnalysisCollection.add({
        'kind': 'govtrack_progress_report',
        'projectId': _projectId,
        'projectName': _projectName,
        'progressPercent': pct,
        'imageUrls': _mlResult!.imageUrls,
        'imageUrl': _mlResult!.imageUrls.isNotEmpty ? _mlResult!.imageUrls.first : null,
        'analysis': _lastAnalysisMap,
        'aiStatus': 'done',
        'submittedByUid': FirebaseAuth.instance.currentUser?.uid,
        'submittedById': user?.id,
        'submittedByName': user?.fullName,
        'submittedByEmail': user?.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _progressStep = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report sent to Admin.'), backgroundColor: AppTheme.softGreen),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: _headerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go(RouteNames.siteManagerHome),
        ),
        title: const Text('GovTrack AI', style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(text: 'AI Assistant'),
            Tab(text: 'Progress Analysis'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildAssistantTab(),
          _buildProgressTab(),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav
          ? const SiteManagerBottomNav(currentIndex: 1)
          : null,
    );
  }

  Widget _buildAssistantTab() {
    const chips = [
      "What's the weather right now?",
      'Summarize my project progress',
      'Low stock / material risks',
      'Safety checklist for today',
      'Delay risks this week',
    ];

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_headerBlue.withValues(alpha: 0.12), _purple.withValues(alpha: 0.08)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _headerBlue.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.psychology_outlined, color: _purple, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Powered by Gemini • Live weather + project data',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _headerBlue,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (_weatherBundle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _LiveWeatherStrip(bundle: _weatherBundle!),
          )
        else if (_projectId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SiteWeatherConditionsCard(
              projectLocation: _projectLocation,
              margin: EdgeInsets.zero,
              compact: true,
            ),
          ),
        if ((_projectName ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.apartment, size: 16, color: _headerBlue.withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _projectName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _chatScroll,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            itemCount: _messages.length,
            itemBuilder: (context, i) => _ChatBubble(message: _messages[i]),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              return FilterChip(
                label: Text(chips[i], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                selected: false,
                onSelected: _chatSending ? null : (_) => _insertChatPrompt(chips[i]),
                backgroundColor: Colors.white,
                side: BorderSide(color: _purple.withValues(alpha: 0.35)),
                labelStyle: const TextStyle(color: _purple),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    enabled: !_chatSending,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Ask about progress, materials, safety, delays…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    onSubmitted: _chatSending ? null : (_) => _sendChat(),
                  ),
                ),
                Material(
                  color: _purple,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _chatSending ? null : _sendChat,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: _chatSending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressTab() {
    final pct = _mlResult?.overallProgressPercent;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProjectInfoCard(projectId: _projectId, projectName: _projectName),
        const SizedBox(height: 14),
        _StepperRow(active: _progressStep),
        if (_progressError != null) ...[
          const SizedBox(height: 12),
          _InlineAlert(
            message: _progressError!,
            onDismiss: () => setState(() => _progressError = null),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera_outlined, color: _purple.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Site photos',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${_photoBytes.length}/10',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.mediumGray,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Upload clear photos of active work areas. ML uses Vision + Gemini on each image.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray, height: 1.35),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _photoBytes.length + (_photoBytes.length < 10 ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == _photoBytes.length) {
                    return Material(
                      color: _purple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _analyzing ? null : _pickPhotos,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _purple.withValues(alpha: 0.5)),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined, color: _purple),
                              SizedBox(height: 4),
                              Text('Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _purple)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_photoBytes[i], fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: _purple,
                          child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _analyzing
                                ? null
                                : () => setState(() {
                                      _photoBytes.removeAt(i);
                                      if (i < _photoNames.length) _photoNames.removeAt(i);
                                      _mlResult = null;
                                      _progressStep = 0;
                                    }),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _analyzing ? null : _runMlAnalysis,
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: _analyzing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_analyzing ? 'Running ML pipeline…' : 'Analyze Progress (ML)'),
          ),
        ),
        if (pct != null) ...[
          const SizedBox(height: 14),
          ConstructionProgressPanel(
            title: 'ML Results',
            overallPercent: pct,
            stages: ConstructionProgressPanel.mlStagesFromMap(_mlResult?.stageProgress),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _headerBlue.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.send_outlined, color: _headerBlue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Submit report to Admin',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _mlResult == null
                    ? 'Run ML analysis first, then send the report for executive review.'
                    : 'Includes photos, labels, and estimated progress %.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _mlResult == null ? null : _sendToAdmin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _headerBlue,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send to Admin'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _GovtrackParsedReply {
  const _GovtrackParsedReply({
    required this.displayText,
    this.summary,
    this.keyPoints = const [],
    this.recommendation,
  });

  final String displayText;
  final String? summary;
  final List<String> keyPoints;
  final String? recommendation;

  factory _GovtrackParsedReply.fromRaw(String raw) {
    if (raw.isEmpty) {
      return const _GovtrackParsedReply(displayText: 'No response.');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final summary = (decoded['summary'] ?? '').toString().trim();
        final keyPoints = (decoded['keyPoints'] as List?)
                ?.map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList() ??
            const <String>[];
        final recommendation = (decoded['recommendation'] ?? '').toString().trim();
        final display = summary.isNotEmpty
            ? summary
            : (keyPoints.isNotEmpty ? keyPoints.join('\n') : raw);
        return _GovtrackParsedReply(
          displayText: display,
          summary: summary.isNotEmpty ? summary : null,
          keyPoints: keyPoints,
          recommendation: recommendation.isNotEmpty ? recommendation : null,
        );
      }
    } catch (_) {}
    return _GovtrackParsedReply(displayText: raw);
  }
}

class _ChatMsg {
  const _ChatMsg({
    required this.isUser,
    required this.text,
    this.summary,
    this.keyPoints = const [],
    this.recommendation,
  });

  factory _ChatMsg.fromParsed(_GovtrackParsedReply p) {
    return _ChatMsg(
      isUser: false,
      text: p.displayText,
      summary: p.summary,
      keyPoints: p.keyPoints,
      recommendation: p.recommendation,
    );
  }

  final bool isUser;
  final String text;
  final String? summary;
  final List<String> keyPoints;
  final String? recommendation;

  String get displayText {
    if (summary != null && summary!.isNotEmpty) return summary!;
    return text;
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final _ChatMsg message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final thinking = message.text == 'Thinking…';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              child: const Icon(Icons.smart_toy_outlined, size: 18, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF7C3AED) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser ? null : Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: isUser
                    ? null
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: thinking
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Analyzing project data…',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                        ),
                      ],
                    )
                  : _AssistantContent(message: message, isUser: isUser),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _AssistantContent extends StatelessWidget {
  const _AssistantContent({required this.message, required this.isUser});
  final _ChatMsg message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(color: isUser ? Colors.white : AppTheme.darkGray, height: 1.4, fontSize: 14);
    if (isUser) {
      return SelectableText(message.text, style: textStyle);
    }
    final summary = message.summary;
    final points = message.keyPoints;
    final rec = message.recommendation;
    if (summary == null && points.isEmpty) {
      return SelectableText(message.text, style: textStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          SelectableText(summary, style: textStyle.copyWith(fontWeight: FontWeight.w700)),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7C3AED))),
                  Expanded(child: SelectableText(p, style: textStyle)),
                ],
              ),
            ),
          ),
        ],
        if (rec != null && rec.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              rec,
              style: textStyle.copyWith(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineAlert extends StatelessWidget {
  const _InlineAlert({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12, height: 1.35),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF991B1B)),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectInfoCard extends StatelessWidget {
  const _ProjectInfoCard({this.projectId, this.projectName});
  final String? projectId;
  final String? projectName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/unnamed.jpg',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: AppTheme.lightGray,
                child: const Icon(Icons.apartment),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  projectName ?? 'No project',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                if (projectId != null)
                  Text(
                    projectId!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.mediumGray),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.active});
  final int active;

  @override
  Widget build(BuildContext context) {
    const steps = ['Upload', 'AI Analysis', 'Results', 'Report'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final leftDone = (i ~/ 2) < active;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: leftDone ? const Color(0xFF7C3AED) : const Color(0xFFE5E7EB),
                ),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isActive = stepIndex <= active;
          final isCurrent = stepIndex == active;
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: isCurrent ? 15 : 13,
                  backgroundColor: isActive ? const Color(0xFF7C3AED) : const Color(0xFFF1F5F9),
                  child: isActive && stepIndex < active
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isActive ? Colors.white : AppTheme.mediumGray,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[stepIndex],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                    color: isActive ? const Color(0xFF7C3AED) : AppTheme.mediumGray,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Compact live weather for GovTrack chat (refreshed before each message).
class _LiveWeatherStrip extends StatelessWidget {
  const _LiveWeatherStrip({required this.bundle});

  final SiteWeatherBundle bundle;

  @override
  Widget build(BuildContext context) {
    final live = bundle.liveReport;
    final now = bundle.now;
    final temp = live?.temperature ?? '${now.temperatureC.toStringAsFixed(0)}°C';
    final humidity = live?.humidity ?? (now.humidity != null ? '${now.humidity}%' : '—');
    final lighting = live?.environmentLighting ?? 'Daytime Operations';
    final rainWarn = live?.rainIsComing == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: rainWarn ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rainWarn ? const Color(0xFFF59E0B) : const Color(0xFF93C5FD),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                live?.isDaylight == false ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                color: live?.isDaylight == false ? const Color(0xFF6366F1) : const Color(0xFFF59E0B),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live site weather',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF1E40AF),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      '$temp • Humidity $humidity • $lighting',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E3A8A),
                          ),
                    ),
                    Text(
                      bundle.locationLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.mediumGray,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (live != null && live.rainForecast.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              live.rainForecast,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: rainWarn ? const Color(0xFFB45309) : const Color(0xFF1E40AF),
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
