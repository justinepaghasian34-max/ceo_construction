import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/govtrack_ai_prompt.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/govtrack_context_builder.dart';
import '../../services/govtrack_progress_ml_service.dart';
import '../../services/site_weather_context_service.dart';
import '../../services/weather_service.dart';
import '../../widgets/common/construction_progress_panel.dart';
import 'widgets/buildiq_gemini_style.dart';
import 'widgets/site_manager_bottom_nav.dart';

/// Resident Engineer BuildIQ: assistant chat + site-photo progress analysis.
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
  static const Color _purple = AppTheme.residentBlue;
  static const Color _headerBlue = AppTheme.residentBlue;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TabController _tabs;

  // Chat
  final _chatController = TextEditingController();
  final _chatScroll = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _chatSending = false;
  bool _composerHasText = false;
  String? _threadId;
  List<BuildIqHistoryItem> _history = [];
  bool _historyLoading = false;
  final Map<String, List<_ChatMsg>> _historyCache = {};
  String? _progressError;
  String? _projectId;
  String? _projectName;
  String? _projectLocation;
  String? _planUrl;
  double? _pinLat;
  double? _pinLon;
  String? _pinLabel;
  List<String> _blueprintUrls = const [];
  List<String> _referencePhotoUrls = const [];
  Map<String, dynamic>? _planAnalysis;
  double? _approvedBudget;
  SiteWeatherBundle? _weatherBundle;
  Map<String, dynamic>? _projectContext; // rich data payload for AI

  // Progress analysis — actual site photos only (no blueprint upload for RE)
  final _imagePicker = ImagePicker();
  final List<Uint8List> _photoBytes = [];
  final List<String> _photoNames = [];

  bool _analyzing = false;
  String _analyzeStageLabel = '';
  int _progressStep = 0;
  GovtrackMlAnalysisResult? _mlResult;
  Map<String, dynamic>? _lastAnalysisMap;

  final _mlService = GovtrackProgressMlService();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _chatController.addListener(_onComposerChanged);
    _loadProject();
    _refreshHistory();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _chatController.removeListener(_onComposerChanged);
    _chatController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _onComposerChanged() {
    final has = _chatController.text.trim().isNotEmpty;
    if (has != _composerHasText) {
      setState(() => _composerHasText = has);
    }
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
    final siteName = bundle.locationLabel.isNotEmpty
        ? bundle.locationLabel
        : (_projectName ?? 'Project Site');

    if (live != null && live.isOffline) {
      return GovtrackAiPrompt.weatherOfflineReply;
    }

    final buf = StringBuffer();

    if (live != null && !live.hasError) {
      buf.writeln('Weather forecast for $siteName:');
      buf.writeln();
      buf.writeln('Current conditions: ${live.temperature}, humidity ${live.humidity}.');
      buf.writeln('Visibility: ${live.environmentLighting}.');
      if (live.rainForecast.isNotEmpty) buf.writeln(live.rainForecast);
      if (!live.isDaylight) {
        buf.writeln('Reminder: check site lighting and wear high-visibility PPE.');
      }
      if (live.rainIsComing) {
        buf.writeln('Cover cement, drywall, and open electrical work before rain arrives.');
      }
    } else {
      final now = bundle.now;
      buf.writeln('Weather at $siteName (current conditions):');
      buf.writeln('  Temperature: ${now.temperatureC.toStringAsFixed(0)}°C');
      if (now.description.isNotEmpty) buf.writeln('  Condition: ${now.description}');
      if (now.feelsLikeC != null) {
        buf.writeln('  Feels like: ${now.feelsLikeC!.toStringAsFixed(0)}°C');
      }
      if (now.humidity != null) buf.writeln('  Humidity: ${now.humidity}%');
      if (now.windSpeedMs != null) {
        buf.writeln('  Wind: ${(now.windSpeedMs! * 3.6).round()} km/h');
      }
      if (bundle.siteAdvice.isNotEmpty) buf.writeln(bundle.siteAdvice);
    }

    if (bundle.forecastDays.isNotEmpty) {
      buf.writeln();
      buf.writeln('7-Day Forecast:');
      for (final d in bundle.forecastDays.take(7)) {
        final dateLabel =
            '${d.date.month}/${d.date.day}';
        final pop =
            d.pop != null ? '${(d.pop! * 100).round()}% rain' : '';
        final extras = [pop].where((s) => s.isNotEmpty).join(' · ');
        buf.writeln(
          '  $dateLabel  ${d.condition}  '
          '${d.maxTempC.toStringAsFixed(0)}° / ${d.minTempC.toStringAsFixed(0)}°'
          '${extras.isNotEmpty ? "  $extras" : ""}',
        );
      }
    }

    buf.writeln();
    buf.writeln('Sources:');
    buf.writeln('- Weather Forecast Feed – $siteName – ${_isoNow()}');
    return buf.toString().trim();
  }

  static String _isoNow() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadProject() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.assignedProjects.isEmpty) return;
    final id = user.assignedProjects.first;
    String name = id;
    String? location;
    String? planUrl;
    double? pinLat;
    double? pinLon;
    String? pinLabel;
    var blueprintUrls = <String>[];
    var referencePhotoUrls = <String>[];
    Map<String, dynamic>? planAnalysis;
    double? budget;
    try {
      final snap =
          await FirebaseService.instance.projectsCollection.doc(id).get();
      final data = (snap.data() as Map?)?.cast<String, dynamic>() ?? {};
      final n = (data['name'] ?? data['projectName'] ?? '').toString().trim();
      if (n.isNotEmpty) name = n;
      final loc = (data['location'] ?? '').toString().trim();
      location = loc.isEmpty ? null : loc;
      planUrl = (data['planUrl'] ?? '').toString().trim();
      if (planUrl.isEmpty) planUrl = null;
      pinLat = (data['latitude'] as num?)?.toDouble();
      pinLon = (data['longitude'] as num?)?.toDouble();
      pinLabel = (data['geoAddress'] ?? location ?? '').toString().trim();
      if (pinLabel.isEmpty) pinLabel = null;
      final pinValid = pinLat != null &&
          pinLon != null &&
          pinLat.abs() <= 90 &&
          pinLon.abs() <= 180;
      if (!pinValid && (location ?? '').isNotEmpty) {
        final geo = await WeatherService.instance
            .resolveOpenMeteoCoordinates(location!);
        if (geo != null) {
          pinLat = geo.lat;
          pinLon = geo.lon;
          pinLabel = geo.label;
        }
      }
      void addUrls(List<String> into, dynamic raw) {
        if (raw is Iterable) {
          for (final item in raw) {
            final v = item.toString().trim();
            if (v.isNotEmpty && !into.contains(v)) into.add(v);
          }
        } else {
          final v = (raw ?? '').toString().trim();
          if (v.isNotEmpty && !into.contains(v)) into.add(v);
        }
      }
      if (planUrl != null) blueprintUrls.add(planUrl);
      addUrls(blueprintUrls, data['blueprintUrls']);
      addUrls(referencePhotoUrls, data['referencePhotoUrls']);
      planAnalysis = (data['planAnalysis'] as Map?)?.cast<String, dynamic>();
      final rawBudget = data['approvedBudget'] ?? planAnalysis?['approvedBudget'];
      if (rawBudget is num) {
        budget = rawBudget.toDouble();
      } else {
        budget = double.tryParse(rawBudget?.toString() ?? '');
      }
    } catch (_) {}

    // Load weather and rich project context in parallel.
    await Future.wait([
      _refreshWeather(),
      _refreshProjectContext(projectId: id, projectName: name, location: location),
    ]);

    if (!mounted) return;
    setState(() {
      _projectId = id;
      _projectName = name;
      _projectLocation = location;
      _planUrl = planUrl;
      _pinLat = pinLat;
      _pinLon = pinLon;
      _pinLabel = pinLabel;
      _blueprintUrls = blueprintUrls;
      _referencePhotoUrls = referencePhotoUrls;
      _planAnalysis = planAnalysis;
      _approvedBudget = budget;
    });
  }

  Future<void> _refreshProjectContext({
    required String projectId,
    required String? projectName,
    required String? location,
  }) async {
    try {
      final ctx = await GovtrackContextBuilder.instance.build(
        projectId: projectId,
        projectName: projectName,
        projectLocation: location,
        weatherBundle: _weatherBundle,
      );
      if (mounted) setState(() => _projectContext = ctx);
    } catch (_) {
      // Context load failed — AI will still work with whatever is available.
    }
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

    _threadId ??= const Uuid().v4();

    setState(() {
      _chatSending = true;
      _messages.add(_ChatMsg(isUser: true, text: text));
      _messages.add(const _ChatMsg(isUser: false, text: 'Thinking…'));
      _chatController.clear();
    });
    _scrollChatToEnd();

    try {
      await _refreshWeather(force: true);
      // Refresh project context if not yet loaded.
      if (_projectContext == null && _projectId != null) {
        await _refreshProjectContext(
          projectId: _projectId!,
          projectName: _projectName,
          location: _projectLocation,
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken(true);

      // Build the site name for the prompt.
      final siteName = (_weatherBundle?.locationLabel.isNotEmpty == true
              ? _weatherBundle!.locationLabel
              : null) ??
          _projectLocation ??
          _projectName ??
          'Project Site';

      // Build weather blocks.
      final live = _weatherBundle?.liveReport;
      final weatherBlock = _weatherBundle != null
          ? GovtrackAiPrompt.liveSiteContextBlock(
              siteName: siteName,
              temperature: live?.temperature ??
                  '${_weatherBundle!.now.temperatureC.toStringAsFixed(0)}°C',
              humidity: live?.humidity ??
                  (_weatherBundle!.now.humidity != null
                      ? '${_weatherBundle!.now.humidity}%'
                      : 'Unavailable'),
              environmentLighting:
                  live?.environmentLighting ?? 'Daytime Operations',
              rainForecast: live?.rainForecast ?? 'No rain data.',
            )
          : '';

      final forecastBlock = (_weatherBundle != null &&
              _weatherBundle!.forecastDays.isNotEmpty)
          ? GovtrackAiPrompt.forecastContextBlock(
              siteName: siteName,
              forecastDays: _weatherBundle!.forecastDays
                  .take(7)
                  .map((d) => {
                        'date':
                            '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}',
                        'condition': d.condition,
                        'minTempC': d.minTempC,
                        'maxTempC': d.maxTempC,
                        'pop': d.pop,
                        'humidity': d.humidity,
                        'windSpeedMs': d.windSpeedMs,
                      })
                  .toList(),
              issuedAt: _weatherBundle!.fetchedAt,
            )
          : '';

      // Build the full system instruction with all data.
      final systemInstruction = _projectName != null
          ? GovtrackAiPrompt.buildFullSystemInstruction(
              projectName: _projectName!,
              projectSiteName: siteName,
              projectContext: _projectContext ?? {'projectId': _projectId},
              weatherBlock: weatherBlock,
              forecastBlock: forecastBlock,
            )
          : null;

      final callable =
          FirebaseFunctions.instance.httpsCallable('govtrackChatGemini');
      final res = await callable
          .call(<String, dynamic>{
            'message': text,
            'history': _chatHistoryPayload(),
            'idToken': idToken,
            'projectId': _projectId,
            'projectName': _projectName,
            // Full structured context for the Cloud Function.
            if (_projectContext != null) 'projectData': _projectContext,
            if (_weatherBundle != null)
              'weatherContext': _weatherBundle!.toAiJson(),
            if (forecastBlock.isNotEmpty)
              'weatherForecastBlock': forecastBlock,
            if (systemInstruction != null)
              'systemInstruction': systemInstruction,
          })
          .timeout(const Duration(seconds: 120));

      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      var rawReply = (data['reply'] ?? data['message'] ?? '').toString().trim();
      if (_isWeatherQuestion(text) &&
          _weatherBundle != null &&
          (rawReply.toLowerCase().contains('cannot find') ||
              rawReply.toLowerCase().contains('tracking metric') ||
              rawReply.toLowerCase().contains('not in the current project') ||
              rawReply.toLowerCase().contains('unavailable') ||
              rawReply.toLowerCase().contains('weather unavailable') ||
              rawReply.toLowerCase().contains('check connection') ||
              rawReply.toLowerCase().contains('do not have verified'))) {
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
          'threadId': _threadId,
          'message': text,
          'reply': rawReply,
          if (_projectId != null) 'projectId': _projectId,
          if (_projectName != null) 'projectName': _projectName,
          'submittedByUid': user?.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _refreshHistory();
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

  void _startNewChat() {
    Navigator.of(context).maybePop();
    setState(() {
      _messages.clear();
      _threadId = null;
      _chatController.clear();
      _composerHasText = false;
    });
  }

  Future<void> _refreshHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (mounted) setState(() => _historyLoading = true);

    QuerySnapshot snap;
    try {
      snap = await FirebaseService.instance.aiAnalysisCollection
          .where('submittedByUid', isEqualTo: uid)
          .where('kind', isEqualTo: 'govtrack_chat')
          .orderBy('createdAt', descending: true)
          .limit(120)
          .get();
    } catch (_) {
      try {
        snap = await FirebaseService.instance.aiAnalysisCollection
            .where('submittedByUid', isEqualTo: uid)
            .limit(120)
            .get();
      } catch (e) {
        developer.log('chat history load failed', error: e);
        if (mounted) setState(() => _historyLoading = false);
        return;
      }
    }

    final grouped = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in snap.docs) {
      final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
      if ((data['kind'] ?? '') != 'govtrack_chat') continue;
      final threadId = (data['threadId'] ?? doc.id).toString();
      grouped.putIfAbsent(threadId, () => []).add(doc);
    }

    final items = <BuildIqHistoryItem>[];
    _historyCache.clear();
    grouped.forEach((id, docs) {
      docs.sort((a, b) {
        final aTime = ((a.data() as Map?)?['createdAt'] as Timestamp?)
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = ((b.data() as Map?)?['createdAt'] as Timestamp?)
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
      final messages = <_ChatMsg>[];
      for (final doc in docs) {
        final data = (doc.data() as Map?)?.cast<String, dynamic>() ?? {};
        final q = (data['message'] ?? '').toString().trim();
        final a = (data['reply'] ?? '').toString().trim();
        if (q.isNotEmpty) messages.add(_ChatMsg(isUser: true, text: q));
        if (a.isNotEmpty) messages.add(_ChatMsg(isUser: false, text: a));
      }
      if (messages.isEmpty) return;
      _historyCache[id] = messages;
      final lastData =
          (docs.last.data() as Map?)?.cast<String, dynamic>() ?? {};
      final updated = (lastData['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now();
      final title = messages.firstWhere((m) => m.isUser,
          orElse: () => messages.first);
      items.add(BuildIqHistoryItem(
        id: id,
        title: title.text,
        updatedAt: updated,
        preview: messages.length > 1 ? messages.last.displayText : '',
      ));
    });
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (!mounted) return;
    setState(() {
      _history = items;
      _historyLoading = false;
    });
  }

  void _openHistoryThread(BuildIqHistoryItem item) {
    Navigator.of(context).maybePop();
    final cached = _historyCache[item.id] ?? const <_ChatMsg>[];
    setState(() {
      _threadId = item.id;
      _messages
        ..clear()
        ..addAll(cached);
    });
    _tabs.animateTo(0);
    _scrollChatToEnd();
  }

  // ── Image pickers (site photos only) ─────────────────────────────────────

  Future<void> _addPhotos(List<XFile> files) async {
    if (files.isEmpty) return;
    final room = 10 - _photoBytes.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 10 site photos.')),
      );
      return;
    }
    for (final f in files.take(room)) {
      _photoBytes.add(await f.readAsBytes());
      _photoNames.add(f.name);
    }
    if (!mounted) return;
    setState(() {
      _progressStep = 0;
      _mlResult = null;
    });
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 85);
      if (!mounted || files.isEmpty) return;
      await _addPhotos(files);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to pick photos: $e')));
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (!mounted || file == null) return;
      await _addPhotos([file]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  // ── Analysis ─────────────────────────────────────────────────────────────

  Future<void> _runMlAnalysis() async {
    if (_projectId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No project assigned.')));
      return;
    }
    if (_photoBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload actual site photos to analyse progress.'),
        ),
      );
      return;
    }
    if (!await _ensureAuth()) return;

    setState(() {
      _analyzing = true;
      _progressStep = 1;
      _progressError = null;
      _analyzeStageLabel = 'Preparing…';
    });

    try {
      final result = await _mlService.analyzeProgressAgainstSavedPlan(
        projectId: _projectId!,
        projectName: _projectName,
        sitePhotoBytes: _photoBytes,
        sitePhotoNames: _photoNames,
        planUrl: _planUrl,
        extraBlueprintUrls: _blueprintUrls,
        referencePhotoUrls: _referencePhotoUrls,
        planAnalysis: _planAnalysis,
        approvedBudget: _approvedBudget,
        onProgress: (stage, done, total) {
          if (!mounted) return;
          setState(() {
            _analyzeStageLabel = stage == 'blueprint'
                ? 'Comparing photos to project blueprint…'
                : 'Analysing site photo $done / $total…';
          });
        },
      );

      final analysisMap = result.toAnalysisMap();
      final pct = result.overallProgressPercent;

      String? syncWarning;
      if (pct != null && _projectId != null) {
        try {
          await FirebaseService.instance.projectsCollection
              .doc(_projectId!)
              .update({
            'progressPercentage': pct,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          syncWarning =
              'Analysis done; project % not synced (${_friendlyError(e)}).';
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
        _analyzeStageLabel = '';
      });

      // Refresh project context so AI knows the updated progress %.
      if (_projectId != null) {
        _refreshProjectContext(
          projectId: _projectId!,
          projectName: _projectName,
          location: _projectLocation,
        ).ignore();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pct == null
                ? 'Analysis complete.'
                : 'Funded-scope progress: ${pct.toStringAsFixed(0)}%',
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
        _analyzeStageLabel = '';
      });
    }
  }

  Future<void> _sendToAdmin() async {
    if (_projectId == null || _mlResult == null) return;
    final pct = (_mlResult!.overallProgressPercent ?? 0).clamp(0, 100);
    final user = AuthService.instance.currentUser;
    try {
      final coverUrl = _mlResult!.imageUrls.isNotEmpty
          ? _mlResult!.imageUrls.first
          : null;
      await FirebaseService.instance.aiAnalysisCollection.add({
        'kind': 'govtrack_progress_report',
        'projectId': _projectId,
        'projectName': _projectName,
        'progressPercent': pct,
        'imageUrls': _mlResult!.imageUrls,
        'imageUrl': coverUrl,
        if (_mlResult!.perImageResults.isNotEmpty)
          'perImageResults': _mlResult!.perImageResults,
        'analysis': _lastAnalysisMap,
        'aiStatus': 'done',
        if (_mlResult!.blueprintUrls.isNotEmpty)
          'blueprintUrls': _mlResult!.blueprintUrls,
        if (_mlResult!.firstWorkArea != null)
          'firstWorkArea': _mlResult!.firstWorkArea,
        if (_mlResult!.budgetedProgressPercent != null)
          'budgetedProgressPercent': _mlResult!.budgetedProgressPercent,
        'submittedByUid': FirebaseAuth.instance.currentUser?.uid,
        'submittedById': user?.id,
        'submittedByName': user?.fullName,
        'submittedByEmail': user?.email,
        'assignedSiteManagerName': user?.fullName,
        'assignedSiteManagerEmail': user?.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      try {
        await FirebaseService.instance.notificationsCollection.add({
          'type': AppConstants.notificationProgressReport,
          'audienceRole': 'admin',
          'targetRole': 'admin',
          'userId': 'admin',
          'title': 'New progress report — ${_projectName ?? 'Site'}',
          'message':
              '${user?.fullName.isNotEmpty == true ? user!.fullName : (user?.email ?? 'Resident Engineer')} submitted a site progress report (${pct.toStringAsFixed(0)}%).',
          'projectId': _projectId,
          'projectName': _projectName,
          if (coverUrl != null) 'imageUrl': coverUrl,
          'createdByUid': FirebaseAuth.instance.currentUser?.uid,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
      if (!mounted) return;
      setState(() => _progressStep = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Report sent to Admin.'),
            backgroundColor: AppTheme.softGreen),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: AppTheme.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      drawer: BuildIqHistoryDrawer(
        items: _history,
        loading: _historyLoading,
        activeId: _threadId,
        onNewChat: _startNewChat,
        onOpen: _openHistoryThread,
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppTheme.residentHeaderGradient,
            ),
          ),
        ),
        leading: IconButton(
          tooltip: 'Chat history',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BuildIqSparkle(size: 18),
            SizedBox(width: 8),
            Text(
              'BuildIQ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go(RouteNames.siteManagerHome),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          indicatorWeight: 2,
          dividerColor: Colors.white24,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Assistant'),
            Tab(text: 'Site Photos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildAssistantTab(),
          ColoredBox(
            color: const Color(0xFFF8FAFC),
            child: _buildProgressTab(),
          ),
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
      'Summarize project progress',
      'Materials status',
      'Pre-pour slab checklist',
      'Safety risks today',
    ];
    final firstName =
        (AuthService.instance.currentUser?.firstName ?? '').trim();
    final hasConversation = _messages.any((m) => m.isUser);
    final live = _weatherBundle?.liveReport;
    final weatherLine = _weatherBundle == null
        ? null
        : [
            live?.temperature ??
                '${_weatherBundle!.now.temperatureC.toStringAsFixed(0)}°C',
            if (_weatherBundle!.locationLabel.isNotEmpty)
              _weatherBundle!.locationLabel,
          ].join(' · ');

    return Column(
      children: [
        Expanded(
          child: hasConversation
              ? ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => BuildIqChatTurn(
                    isUser: _messages[i].isUser,
                    text: _messages[i].displayText,
                  ),
                )
              : BuildIqGreeting(
                  firstName: firstName,
                  chips: chips,
                  onChip: _insertChatPrompt,
                  projectName: _projectName,
                  weatherLine: weatherLine,
                ),
        ),
        BuildIqComposer(
          controller: _chatController,
          enabled: !_chatSending,
          busy: _chatSending,
          hasText: _composerHasText,
          onSend: _sendChat,
        ),
      ],
    );
  }

  Widget _buildProgressTab() {
    final result = _mlResult;
    final pct = result?.overallProgressPercent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _StepperRow(active: _progressStep),
        if (_progressError != null) ...[
          const SizedBox(height: 10),
          _InlineAlert(
            message: _progressError!,
            onDismiss: () => setState(() => _progressError = null),
          ),
        ],
        const SizedBox(height: 14),
        _SavedBlueprintBanner(
          planUrl: _planUrl,
          budget: _approvedBudget,
        ),
        const SizedBox(height: 14),
        _ProjectLocationPinCard(
          lat: _pinLat,
          lon: _pinLon,
          label: _pinLabel ?? _projectLocation,
          projectName: _projectName,
        ),
        const SizedBox(height: 14),
        _UploadSection(
          sectionColor: _purple,
          icon: Icons.photo_camera_outlined,
          title: 'Site Photos',
          subtitle:
              'Upload actual site photos. AI compares them to the project blueprint and scores only the budgeted area — not the whole drawing.',
          count: _photoBytes.length,
          max: 10,
          imageBytes: _photoBytes,
          imageNames: _photoNames,
          disabled: _analyzing,
          badgeLabel: 'Site',
          badgeColor: _purple,
          onAdd: _pickPhotos,
          onAddCamera: _capturePhoto,
          onRemove: (i) => setState(() {
            _photoBytes.removeAt(i);
            if (i < _photoNames.length) _photoNames.removeAt(i);
            _mlResult = null;
            _progressStep = 0;
          }),
          hint: _photoBytes.isEmpty
              ? const _UploadHint(
                  icon: Icons.photo_camera_outlined,
                  color: AppTheme.residentBlue,
                  lines: [
                    'Take or attach real site photos only',
                    '2–6 photos recommended · max 10',
                  ],
                )
              : null,
        ),
        const SizedBox(height: 16),
        _AnalyseButton(
          analyzing: _analyzing,
          stageLabel: _analyzeStageLabel,
          hasPhotos: _photoBytes.isNotEmpty,
          onPressed: _analyzing ? null : _runMlAnalysis,
        ),
        if (result != null) ...[
          const SizedBox(height: 20),
          if (pct != null)
            ConstructionProgressPanel(
              title: 'Funded-scope progress',
              overallPercent: pct,
              stages: ConstructionProgressPanel.mlStagesFromMap(
                  result.stageProgress),
            ),
          if (result.firstWorkArea != null ||
              result.workSequence.isNotEmpty ||
              result.excludedFromBudget.isNotEmpty) ...[
            const SizedBox(height: 14),
            _BudgetScopeCard(result: result),
          ],
          if ((result.crossReferenceNarrative ?? '').isNotEmpty) ...[
            const SizedBox(height: 14),
            _NarrativeCard(narrative: result.crossReferenceNarrative!),
          ],
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _headerBlue.withValues(alpha: 0.12)),
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
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                result == null
                    ? 'Analyse site photos first, then send the report.'
                    : 'Ready to send this progress report to admin.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.mediumGray),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: result == null ? null : _sendToAdmin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _headerBlue,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
    if (isUser) return text;
    if (keyPoints.isEmpty && (summary == null || summary!.isEmpty)) {
      return text;
    }
    final buf = StringBuffer();
    if (summary != null && summary!.isNotEmpty) buf.writeln(summary);
    for (final p in keyPoints) {
      buf.writeln('- $p');
    }
    if (recommendation != null && recommendation!.isNotEmpty) {
      buf.writeln();
      buf.writeln(recommendation);
    }
    final assembled = buf.toString().trim();
    return assembled.isEmpty ? text : assembled;
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
                  color: leftDone ? AppTheme.residentBlue : const Color(0xFFE5E7EB),
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
                  backgroundColor: isActive ? AppTheme.residentBlue : const Color(0xFFF1F5F9),
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
                    color: isActive ? AppTheme.residentBlue : AppTheme.mediumGray,
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


// ═══════════════════════════════════════════════════════════════════════════
// Progress tab — private widget classes
// ═══════════════════════════════════════════════════════════════════════════

// ── Upload section ───────────────────────────────────────────────────────────

class _UploadSection extends StatelessWidget {
  const _UploadSection({
    required this.sectionColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.max,
    required this.imageBytes,
    required this.imageNames,
    required this.disabled,
    required this.badgeLabel,
    required this.badgeColor,
    required this.onAdd,
    required this.onRemove,
    this.onAddCamera,
    this.hint,
  });

  final Color sectionColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final int max;
  final List<Uint8List> imageBytes;
  final List<String> imageNames;
  final bool disabled;
  final String badgeLabel;
  final Color badgeColor;
  final VoidCallback onAdd;
  final VoidCallback? onAddCamera;
  final void Function(int index) onRemove;
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: sectionColor.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(
                    color: sectionColor.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: sectionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: sectionColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.darkGray,
                        ),
                  ),
                ),
                // Count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? sectionColor.withValues(alpha: 0.15)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count / $max',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: count > 0 ? sectionColor : AppTheme.mediumGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mediumGray,
                    height: 1.4,
                  ),
            ),
          ),
          if (onAddCamera != null && count < max)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: disabled ? null : onAddCamera,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Take photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: sectionColor,
                        side: BorderSide(color: sectionColor.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disabled ? null : onAdd,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                      style: FilledButton.styleFrom(
                        backgroundColor: sectionColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (hint != null && count == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: hint!,
            ),
          // Image grid
          if (count > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: count,
                itemBuilder: (context, i) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(imageBytes[i], fit: BoxFit.cover),
                      ),
                      // Index badge
                      Positioned(
                        top: 4,
                        left: 4,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: badgeColor,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      // Remove button
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: disabled ? null : () => onRemove(i),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 13),
                          ),
                        ),
                      ),
                      // Label tag
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800),
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
}

// ── Upload hint ──────────────────────────────────────────────────────────────

class _UploadHint extends StatelessWidget {
  const _UploadHint({
    required this.icon,
    required this.color,
    required this.lines,
  });

  final IconData icon;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines
                  .map((l) => Text(l,
                      style: TextStyle(
                          fontSize: 11,
                          color: color.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w600)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Analyse button ────────────────────────────────────────────────────────────

class _AnalyseButton extends StatelessWidget {
  const _AnalyseButton({
    required this.analyzing,
    required this.stageLabel,
    required this.hasPhotos,
    required this.onPressed,
  });

  final bool analyzing;
  final String stageLabel;
  final bool hasPhotos;
  final VoidCallback? onPressed;

  String get _buttonLabel {
    if (analyzing) {
      return stageLabel.isNotEmpty ? stageLabel : 'Analysing site photos…';
    }
    if (hasPhotos) return 'Analyse site photos';
    return 'Add site photos to analyse';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: hasPhotos ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.residentBlue,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: analyzing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome),
        label: Text(
          _buttonLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}


// ── Cross-reference narrative card ───────────────────────────────────────────

class _NarrativeCard extends StatefulWidget {
  const _NarrativeCard({required this.narrative});
  final String narrative;

  @override
  State<_NarrativeCard> createState() => _NarrativeCardState();
}

class _NarrativeCardState extends State<_NarrativeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const blue = AppTheme.residentBlue;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: blue.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.psychology_outlined, color: blue, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text('AI Analysis',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900, color: blue)),
            ),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Less' : 'More',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: blue),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            widget.narrative,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.residentBlue,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProjectLocationPinCard extends StatelessWidget {
  const _ProjectLocationPinCard({
    this.lat,
    this.lon,
    this.label,
    this.projectName,
  });

  final double? lat;
  final double? lon;
  final String? label;
  final String? projectName;

  bool get _hasPin {
    final la = lat;
    final lo = lon;
    return la != null &&
        lo != null &&
        la.abs() <= 90 &&
        lo.abs() <= 180;
  }

  @override
  Widget build(BuildContext context) {
    final title = (label ?? '').trim().isNotEmpty
        ? label!.trim()
        : (projectName ?? 'Project site');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: AppTheme.residentBlue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project location pin',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _hasPin
                            ? title
                            : 'No pin yet. Admin location from Create Project will drop the pin here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.mediumGray,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_hasPin)
            SizedBox(
              height: 180,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(lat!, lon!),
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom |
                        InteractiveFlag.drag |
                        InteractiveFlag.doubleTapZoom,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    tileProvider: CancellableNetworkTileProvider(),
                    userAgentPackageName: 'com.ceoconstruction.monitoring',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(lat!, lon!),
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.location_on,
                          color: AppTheme.residentBlue,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SavedBlueprintBanner extends StatelessWidget {
  const _SavedBlueprintBanner({this.planUrl, this.budget});

  final String? planUrl;
  final double? budget;

  @override
  Widget build(BuildContext context) {
    final hasPlan = (planUrl ?? '').isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasPlan ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPlan
              ? AppTheme.residentBlue.withValues(alpha: 0.18)
              : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasPlan ? Icons.architecture : Icons.info_outline,
            color: hasPlan ? AppTheme.residentBlue : const Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPlan
                      ? 'Project blueprint on file'
                      : 'No blueprint on this project yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: hasPlan
                        ? AppTheme.residentBlue
                        : const Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPlan
                      ? 'Photos are compared to the plan Admin saved at create. Only the budgeted part of the drawing counts toward %.${budget != null ? ' Budget: ${budget!.toStringAsFixed(0)}.' : ''}'
                      : 'Ask Admin to upload the blueprint on Create/Edit Project so AI can score funded scope and tell you which side to work first.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mediumGray,
                        height: 1.4,
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

class _BudgetScopeCard extends StatelessWidget {
  const _BudgetScopeCard({required this.result});
  final GovtrackMlAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Blueprint vs funded scope',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Text(
            'The whole sheet is not the project. Extra areas on the drawing stay out of % if they are not in the budget.',
            style: TextStyle(
                color: AppTheme.mediumGray, fontSize: 12, height: 1.4),
          ),
          if ((result.firstWorkArea ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Work this side first',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 4),
            Text(result.firstWorkArea!,
                style: const TextStyle(height: 1.4, fontSize: 13.5)),
          ],
          if (result.workSequence.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Sequence',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 4),
            for (var i = 0; i < result.workSequence.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${i + 1}. ${result.workSequence[i]}',
                    style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
          ],
          if (result.includedInBudget.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('In budget: ${result.includedInBudget.take(6).join(', ')}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.mediumGray)),
          ],
          if (result.excludedFromBudget.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Drawn, not funded: ${result.excludedFromBudget.take(6).join(', ')}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.mediumGray),
            ),
          ],
        ],
      ),
    );
  }
}
